use std::sync::Arc;
use std::time::Duration;

use super::model::{Device, DeviceKind};
use super::runner::{CommandResult, CommandRunner, ProcessRunner};
use super::simctl_parser;

const XCRUN: &str = "/usr/bin/xcrun";
const OPEN: &str = "/usr/bin/open";
const BOOT_TIMEOUT: Duration = Duration::from_secs(120);
const ALREADY_BOOTED: &str = "current state: Booted";

pub struct SimctlService {
    runner: Arc<dyn CommandRunner>,
}

impl Default for SimctlService {
    fn default() -> Self {
        Self::new(Arc::new(ProcessRunner))
    }
}

impl SimctlService {
    pub fn new(runner: Arc<dyn CommandRunner>) -> Self {
        Self { runner }
    }

    /// iPhone and iPad simulators of every installed runtime.
    pub fn list_devices(&self) -> Vec<Device> {
        let devices = self.runner.run_default(XCRUN, &["simctl", "list", "devices", "available", "--json"]);
        if !devices.succeeded() {
            eprintln!("simctl list devices failed: {}", devices.trimmed_output());
            return Vec::new();
        }

        let runtimes = self.runner.run_default(XCRUN, &["simctl", "list", "runtimes", "--json"]);
        let runtimes_json = runtimes.succeeded().then_some(runtimes.output.as_str());

        match simctl_parser::parse(&devices.output, runtimes_json) {
            Ok(list) => list.into_iter().filter(|d| matches!(d.kind, DeviceKind::Iphone | DeviceKind::Ipad)).collect(),
            Err(e) => {
                eprintln!("Could not read simctl output: {e}");
                Vec::new()
            }
        }
    }

    pub fn boot(&self, udid: &str) -> CommandResult {
        let boot = self.runner.run_default(XCRUN, &["simctl", "boot", udid]);
        if !boot.succeeded() && !boot.output.contains(ALREADY_BOOTED) {
            return boot;
        }

        let open = self.runner.run_default(OPEN, &["-a", "Simulator", "--args", "-CurrentDeviceUDID", udid]);
        if !open.succeeded() {
            eprintln!("Could not open Simulator.app: {}", open.trimmed_output());
        }
        self.runner.run(XCRUN, &["simctl", "bootstatus", udid], BOOT_TIMEOUT)
    }

    /// `target` is a UDID, or "booted" for whichever simulator is running.
    pub fn open_url(&self, url: &str, target: &str) -> CommandResult {
        self.runner.run_default(XCRUN, &["simctl", "openurl", target, url])
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::simctl_parser::fixtures::*;
    use crate::device::testing::{strings, FakeRunner};

    fn service(runner: &Arc<FakeRunner>) -> SimctlService {
        SimctlService::new(runner.clone())
    }

    fn standard_runner() -> Arc<FakeRunner> {
        Arc::new(FakeRunner::new(|_, args| {
            if args.contains(&"runtimes") {
                CommandResult::new(RUNTIMES, 0)
            } else if args.contains(&"devices") {
                CommandResult::new(DEVICES, 0)
            } else {
                CommandResult::new("", 0)
            }
        }))
    }

    #[test]
    fn lists_iphones_and_ipads_but_not_watches() {
        let devices = service(&standard_runner()).list_devices();

        assert!(devices.iter().all(|d| matches!(d.kind, DeviceKind::Iphone | DeviceKind::Ipad)));
        assert!(devices.iter().any(|d| d.kind == DeviceKind::Ipad));
        assert!(devices.iter().any(|d| d.kind == DeviceKind::Iphone));
    }

    #[test]
    fn returns_an_empty_list_when_simctl_fails() {
        let runner = Arc::new(FakeRunner::new(|_, _| CommandResult::new("boom", 1)));

        assert!(service(&runner).list_devices().is_empty());
    }

    #[test]
    fn returns_an_empty_list_when_simctl_prints_something_unreadable() {
        let runner = Arc::new(FakeRunner::new(|_, _| CommandResult::new("garbage", 0)));

        assert!(service(&runner).list_devices().is_empty());
    }

    #[test]
    fn boot_waits_for_the_device_after_starting_it_and_opens_simulator_on_that_device() {
        let runner = Arc::new(FakeRunner::silent());

        let result = service(&runner).boot("UDID-1");

        let calls = runner.calls();
        assert!(result.succeeded());
        assert_eq!(calls[0], strings(&["/usr/bin/xcrun", "simctl", "boot", "UDID-1"]));
        assert_eq!(calls[1], strings(&["/usr/bin/open", "-a", "Simulator", "--args", "-CurrentDeviceUDID", "UDID-1"]));
        assert_eq!(calls[2], strings(&["/usr/bin/xcrun", "simctl", "bootstatus", "UDID-1"]));
    }

    #[test]
    fn booting_an_already_booted_device_is_not_an_error() {
        let runner = Arc::new(FakeRunner::new(|_, args| {
            if args.contains(&"boot") {
                CommandResult::new("Unable to boot device in current state: Booted", 149)
            } else {
                CommandResult::new("", 0)
            }
        }));

        assert!(service(&runner).boot("UDID-1").succeeded());
    }

    #[test]
    fn boot_reports_a_real_failure_and_stops() {
        let runner = Arc::new(FakeRunner::new(|_, _| CommandResult::new("Invalid device", 164)));

        let result = service(&runner).boot("nope");

        assert!(!result.succeeded());
        assert_eq!(runner.calls().len(), 1);
    }

    #[test]
    fn opens_the_url_on_the_given_target_as_one_argument_without_a_shell() {
        let runner = Arc::new(FakeRunner::silent());
        let url = "myapp://x?a=1&b=$(whoami);ls";

        service(&runner).open_url(url, "UDID-1");

        assert_eq!(runner.calls(), vec![strings(&["/usr/bin/xcrun", "simctl", "openurl", "UDID-1", url])]);
    }

    #[test]
    fn real_simctl_returns_only_valid_udids() {
        if !std::path::Path::new(XCRUN).exists() {
            return;
        }
        let is_uuid = |id: &str| {
            let groups: Vec<&str> = id.split('-').collect();
            let lengths: Vec<usize> = groups.iter().map(|g| g.len()).collect();
            lengths == [8, 4, 4, 4, 12] && id.chars().all(|c| c == '-' || c.is_ascii_hexdigit())
        };

        let devices = SimctlService::default().list_devices();

        assert!(devices.iter().all(|d| is_uuid(&d.id)), "{devices:?}");
    }
}
