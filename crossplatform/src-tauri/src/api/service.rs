use std::sync::Arc;

use serde::Serialize;

use crate::device::adb::{AdbService, HostEnv, AVD_PREFIX};
use crate::device::model::{Device, Platform};
use crate::device::runner::{CommandResult, CommandRunner, ProcessRunner};
#[cfg(target_os = "macos")]
use crate::device::simctl::SimctlService;

use super::url::is_link;

pub const NO_EMULATOR_MESSAGE: &str = "No running emulator. Start one first.";
pub const SEVERAL_EMULATORS_MESSAGE: &str = "Several emulators are running. Pick an Emulator Target.";
pub const INVALID_LINK_MESSAGE: &str = "Invalid Deeplink URL";
pub const IOS_UNAVAILABLE_MESSAGE: &str = "iOS Simulator is only available on macOS.";
pub const NO_XCODE_MESSAGE: &str = "Xcode command line tools not found. Run `xcode-select --install`.";
const ALREADY_RUNNING_MESSAGE: &str = "This emulator is already running.";

/// The result of an action, always shown to the user as text.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct Outcome {
    pub ok: bool,
    pub message: String,
}

impl Outcome {
    pub fn success(message: impl Into<String>) -> Self {
        Self { ok: true, message: message.into() }
    }

    pub fn failure(message: impl Into<String>) -> Self {
        Self { ok: false, message: message.into() }
    }

    fn from(result: CommandResult, success_message: impl FnOnce() -> String) -> Self {
        let text = result.trimmed_output();
        if result.succeeded() {
            Self::success(if text.is_empty() { success_message() } else { text.to_string() })
        } else {
            Self::failure(if text.is_empty() { format!("Failed (exit code {})", result.exit_code) } else { text.to_string() })
        }
    }
}

/// Whether the tools a platform needs are installed. `message` says what is missing.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct ToolStatus {
    pub platform: Platform,
    pub ok: bool,
    pub message: Option<String>,
}

/// Where commands run: the real machine, or a fake in tests.
#[derive(Clone)]
pub struct Backend {
    runner: Arc<dyn CommandRunner>,
    env: HostEnv,
}

impl Backend {
    pub fn system() -> Self {
        Self { runner: Arc::new(ProcessRunner), env: HostEnv::current() }
    }

    pub fn new(runner: Arc<dyn CommandRunner>, env: HostEnv) -> Self {
        Self { runner, env }
    }

    fn adb(&self, adb_path: &str) -> AdbService {
        AdbService::new(self.runner.clone(), self.env.clone()).with_preferred_adb(adb_path)
    }

    #[cfg(target_os = "macos")]
    fn simctl(&self) -> SimctlService {
        SimctlService::new(self.runner.clone())
    }

    /// iOS is listed only where Xcode exists, so Windows and Linux show Android alone.
    pub fn platforms(&self) -> Vec<Platform> {
        let mut platforms = Vec::new();
        if cfg!(target_os = "macos") {
            platforms.push(Platform::Ios);
        }
        platforms.push(Platform::Android);
        platforms
    }

    pub fn tool_status(&self, platform: Platform, adb_path: &str) -> ToolStatus {
        let missing = match platform {
            Platform::Android => self.adb(adb_path).missing_tool_message().map(String::from),
            Platform::Ios => ios_missing_message(),
        };
        ToolStatus { platform, ok: missing.is_none(), message: missing }
    }

    pub fn adb_paths(&self) -> Vec<String> {
        self.adb("").adb_paths()
    }

    pub fn list_devices(&self, platform: Platform, adb_path: &str) -> Result<Vec<Device>, String> {
        match platform {
            Platform::Android => Ok(self.adb(adb_path).list_devices()),
            Platform::Ios => self.list_ios(),
        }
    }

    pub fn boot_device(&self, platform: Platform, id: &str, adb_path: &str) -> Outcome {
        match platform {
            Platform::Android => match id.strip_prefix(AVD_PREFIX) {
                Some(avd) => Outcome::from(self.adb(adb_path).boot(avd), || format!("Booted {avd}")),
                None => Outcome::success(ALREADY_RUNNING_MESSAGE),
            },
            Platform::Ios => self.boot_ios(id),
        }
    }

    /// `target` is the chosen device id; without one the only running device is used.
    pub fn open_deeplink(&self, platform: Platform, url: &str, target: Option<&str>, package: Option<&str>, adb_path: &str) -> Outcome {
        let url = url.trim();
        if !is_link(url) {
            return Outcome::failure(INVALID_LINK_MESSAGE);
        }
        let target = target.map(str::trim).filter(|t| !t.is_empty());
        let outcome = match platform {
            Platform::Android => self.open_on_android(url, target, package.map(str::trim).filter(|p| !p.is_empty()), adb_path),
            Platform::Ios => self.open_on_ios(url, target),
        };
        if outcome.ok { Outcome { message: opened_message(url, &outcome.message), ..outcome } } else { outcome }
    }

    fn open_on_android(&self, url: &str, target: Option<&str>, package: Option<&str>, adb_path: &str) -> Outcome {
        let service = self.adb(adb_path);
        if let Some(message) = service.missing_tool_message() {
            return Outcome::failure(message);
        }

        let serial = match target {
            Some(serial) if serial.starts_with(AVD_PREFIX) => return Outcome::failure("Start this emulator first."),
            Some(serial) => serial.to_string(),
            None => {
                let running: Vec<Device> = service.list_devices().into_iter().filter(|d| d.is_booted).collect();
                match running.as_slice() {
                    [] => return Outcome::failure(NO_EMULATOR_MESSAGE),
                    [only] => only.id.clone(),
                    _ => return Outcome::failure(SEVERAL_EMULATORS_MESSAGE),
                }
            }
        };
        Outcome::from(service.open_url(url, &serial, package), String::new)
    }

    #[cfg(target_os = "macos")]
    fn list_ios(&self) -> Result<Vec<Device>, String> {
        Ok(self.simctl().list_devices())
    }

    #[cfg(not(target_os = "macos"))]
    fn list_ios(&self) -> Result<Vec<Device>, String> {
        Err(IOS_UNAVAILABLE_MESSAGE.to_string())
    }

    #[cfg(target_os = "macos")]
    fn boot_ios(&self, udid: &str) -> Outcome {
        Outcome::from(self.simctl().boot(udid), || "Booted".to_string())
    }

    #[cfg(not(target_os = "macos"))]
    fn boot_ios(&self, _udid: &str) -> Outcome {
        Outcome::failure(IOS_UNAVAILABLE_MESSAGE)
    }

    #[cfg(target_os = "macos")]
    fn open_on_ios(&self, url: &str, target: Option<&str>) -> Outcome {
        Outcome::from(self.simctl().open_url(url, target.unwrap_or("booted")), String::new)
    }

    #[cfg(not(target_os = "macos"))]
    fn open_on_ios(&self, _url: &str, _target: Option<&str>) -> Outcome {
        Outcome::failure(IOS_UNAVAILABLE_MESSAGE)
    }
}

/// The adb output when it has something to say, otherwise a plain confirmation.
fn opened_message(url: &str, output: &str) -> String {
    if output.is_empty() { format!("Opened {url}") } else { output.to_string() }
}

#[cfg(target_os = "macos")]
fn ios_missing_message() -> Option<String> {
    (!std::path::Path::new("/usr/bin/xcrun").exists()).then(|| NO_XCODE_MESSAGE.to_string())
}

#[cfg(not(target_os = "macos"))]
fn ios_missing_message() -> Option<String> {
    Some(IOS_UNAVAILABLE_MESSAGE.to_string())
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::adb::Os;
    use crate::device::testing::{FakeRunner, ADB_DEVICES};

    const ADB: &str = "/sdk/platform-tools/adb";

    fn env_with_adb() -> HostEnv {
        HostEnv {
            os: Os::Linux,
            vars: [("ANDROID_HOME".to_string(), "/sdk".to_string())].into(),
            home: "/home/a".into(),
            is_executable: Arc::new(|path| path == ADB || path == "/sdk/emulator/emulator"),
        }
    }

    fn env_without_tools() -> HostEnv {
        HostEnv { is_executable: Arc::new(|_| false), ..env_with_adb() }
    }

    fn backend(runner: &Arc<FakeRunner>, env: HostEnv) -> Backend {
        Backend::new(runner.clone(), env)
    }

    /// Answers `adb devices` with `listing`, the AVD name query with `Pixel_8`, and everything else with `reply`.
    fn adb_runner(listing: &'static str, reply: &'static str, exit_code: i32) -> Arc<FakeRunner> {
        Arc::new(FakeRunner::new(move |_, args| {
            if args.first() == Some(&"devices") {
                CommandResult::new(listing, 0)
            } else if args.contains(&"avd") {
                CommandResult::new("Pixel_8\nOK", 0)
            } else if args.contains(&"am") {
                CommandResult::new(reply, exit_code)
            } else {
                CommandResult::new("", 0)
            }
        }))
    }

    const ONE_EMULATOR: &str = "List of devices attached\nemulator-5554\tdevice product:sdk model:Pixel_8 device:emu\n";
    const TWO_EMULATORS: &str = "List of devices attached\nemulator-5554\tdevice\nemulator-5556\tdevice\n";

    #[test]
    fn windows_and_linux_offer_android_only_while_macos_adds_ios_first() {
        let backend = backend(&Arc::new(FakeRunner::silent()), env_with_adb());

        let platforms = backend.platforms();

        if cfg!(target_os = "macos") {
            assert_eq!(platforms, vec![Platform::Ios, Platform::Android]);
        } else {
            assert_eq!(platforms, vec![Platform::Android]);
        }
    }

    #[cfg(not(target_os = "macos"))]
    #[test]
    fn ios_requests_are_refused_off_macos() {
        let backend = backend(&Arc::new(FakeRunner::silent()), env_with_adb());

        assert!(backend.list_devices(Platform::Ios, "").is_err());
        assert!(!backend.boot_device(Platform::Ios, "UDID", "").ok);
        assert!(!backend.open_deeplink(Platform::Ios, "myapp://x", None, None, "").ok);
        assert!(!backend.tool_status(Platform::Ios, "").ok);
    }

    #[test]
    fn tool_status_reports_missing_adb_and_stays_ok_when_found() {
        let runner = Arc::new(FakeRunner::silent());

        let missing = backend(&runner, env_without_tools()).tool_status(Platform::Android, "");
        let found = backend(&runner, env_with_adb()).tool_status(Platform::Android, "");

        assert!(!missing.ok);
        assert!(missing.message.unwrap().contains("adb not found"));
        assert!(found.ok);
        assert_eq!(found.message, None);
    }

    #[test]
    fn adb_paths_lists_the_installed_adb() {
        let backend = backend(&Arc::new(FakeRunner::silent()), env_with_adb());

        assert_eq!(backend.adb_paths(), vec![ADB.to_string()]);
    }

    #[test]
    fn lists_android_devices_through_adb() {
        let runner = Arc::new(FakeRunner::new(|_, args| match args.first() {
            Some(&"devices") => CommandResult::new(ADB_DEVICES, 0),
            _ => CommandResult::new("", 1),
        }));

        let devices = backend(&runner, env_with_adb()).list_devices(Platform::Android, "").unwrap();

        assert!(devices.iter().all(|d| d.platform() == Platform::Android));
        assert!(!devices.is_empty());
    }

    #[test]
    fn rejects_links_without_a_scheme_before_running_anything() {
        let runner = Arc::new(FakeRunner::silent());

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "  not a link ", None, None, "");

        assert_eq!(outcome, Outcome::failure(INVALID_LINK_MESSAGE));
        assert!(runner.calls().is_empty());
    }

    #[test]
    fn opens_the_link_on_the_only_running_emulator_with_the_package() {
        let runner = adb_runner(ONE_EMULATOR, "Starting: Intent", 0);

        let outcome = backend(&runner, env_with_adb())
            .open_deeplink(Platform::Android, " myapp://a?b=1&c=2 ", None, Some(" com.example "), "");

        assert!(outcome.ok, "{outcome:?}");
        let start = runner.calls().into_iter().find(|c| c.contains(&"am".to_string())).unwrap();
        assert_eq!(&start[..3], [ADB, "-s", "emulator-5554"]);
        assert!(start.contains(&"'myapp://a?b=1&c=2'".to_string()));
        assert!(start.windows(2).any(|w| w == ["-p", "'com.example'"]));
    }

    #[test]
    fn says_so_when_the_link_opened_without_any_output() {
        let runner = adb_runner(ONE_EMULATOR, "", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", None, None, "");

        assert_eq!(outcome, Outcome::success("Opened myapp://x"));
    }

    #[test]
    fn asks_for_a_target_when_several_emulators_run() {
        let runner = adb_runner(TWO_EMULATORS, "", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", None, None, "");

        assert_eq!(outcome, Outcome::failure(SEVERAL_EMULATORS_MESSAGE));
    }

    #[test]
    fn asks_to_start_an_emulator_when_none_runs() {
        let runner = adb_runner("List of devices attached\n", "", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", None, None, "");

        assert_eq!(outcome, Outcome::failure(NO_EMULATOR_MESSAGE));
    }

    #[test]
    fn uses_the_chosen_target_even_when_several_run() {
        let runner = adb_runner(TWO_EMULATORS, "", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", Some("emulator-5556"), None, "");

        assert!(outcome.ok);
        assert!(runner.calls().iter().any(|c| c.contains(&"emulator-5556".to_string()) && c.contains(&"am".to_string())));
    }

    #[test]
    fn refuses_a_target_that_is_not_started() {
        let runner = adb_runner(ONE_EMULATOR, "", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", Some("avd:Pixel_8"), None, "");

        assert!(!outcome.ok);
        assert!(runner.calls().is_empty());
    }

    #[test]
    fn reports_a_link_no_app_handles_as_a_failure() {
        let runner = adb_runner(ONE_EMULATOR, "Error: Activity not started, unable to resolve Intent", 0);

        let outcome = backend(&runner, env_with_adb()).open_deeplink(Platform::Android, "myapp://x", None, None, "");

        assert!(!outcome.ok);
        assert!(outcome.message.contains("unable to resolve"));
    }

    #[test]
    fn reports_missing_adb_when_opening_a_link() {
        let runner = Arc::new(FakeRunner::silent());

        let outcome = backend(&runner, env_without_tools()).open_deeplink(Platform::Android, "myapp://x", None, None, "");

        assert!(!outcome.ok);
        assert!(outcome.message.contains("adb not found"));
    }

    #[test]
    fn starting_a_running_emulator_is_not_an_error() {
        let runner = Arc::new(FakeRunner::silent());

        let outcome = backend(&runner, env_with_adb()).boot_device(Platform::Android, "emulator-5554", "");

        assert!(outcome.ok);
        assert!(runner.calls().is_empty());
    }

    #[test]
    fn boots_a_stopped_emulator_by_its_avd_name() {
        let runner = Arc::new(FakeRunner::new(|_, args| {
            if args.first() == Some(&"devices") {
                CommandResult::new(ONE_EMULATOR, 0)
            } else if args.contains(&"avd") {
                CommandResult::new("Pixel_8\nOK", 0)
            } else if args.contains(&"sys.boot_completed") {
                CommandResult::new("1", 0)
            } else {
                CommandResult::new("", 0)
            }
        }));

        let outcome = backend(&runner, env_with_adb()).boot_device(Platform::Android, "avd:Pixel_8", "");

        assert!(outcome.ok, "{outcome:?}");
        assert!(outcome.message.contains("Pixel_8"));
    }

    #[test]
    fn a_failed_command_without_output_still_says_something() {
        let outcome = Outcome::from(CommandResult::new("", 3), String::new);

        assert_eq!(outcome, Outcome::failure("Failed (exit code 3)"));
    }
}
