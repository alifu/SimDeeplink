use std::collections::{HashMap, HashSet};
use std::sync::Arc;
use std::thread;
use std::time::{Duration, Instant};

use super::adb_parser::{self, is_avd_name};
use super::model::{Device, DeviceKind};
use super::runner::{CommandResult, CommandRunner, ProcessRunner};

pub const AVD_PREFIX: &str = "avd:";
pub const MISSING_ADB_MESSAGE: &str = "adb not found. Install the Android SDK platform-tools or set ANDROID_HOME.";
pub const MISSING_EMULATOR_MESSAGE: &str =
    "Android emulator not found. Install it with the Android SDK or set ANDROID_HOME.";

const ANDROID_RUNTIME: &str = "Android";
const DEFAULT_BOOT_TIMEOUT: Duration = Duration::from_secs(120);
const DEFAULT_POLL_INTERVAL: Duration = Duration::from_secs(2);

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Os {
    MacOs,
    Linux,
    Windows,
}

impl Os {
    pub fn current() -> Self {
        if cfg!(target_os = "macos") {
            Os::MacOs
        } else if cfg!(windows) {
            Os::Windows
        } else {
            Os::Linux
        }
    }

    fn separator(self) -> &'static str {
        if self == Os::Windows {
            "\\"
        } else {
            "/"
        }
    }

    fn path_list_separator(self) -> char {
        if self == Os::Windows {
            ';'
        } else {
            ':'
        }
    }

    fn exe_suffix(self) -> &'static str {
        if self == Os::Windows {
            ".exe"
        } else {
            ""
        }
    }
}

/// Everything the tool lookup reads from the machine. Injected in tests, so the layouts of all three
/// operating systems can be checked on any of them.
#[derive(Clone)]
pub struct HostEnv {
    pub os: Os,
    pub vars: HashMap<String, String>,
    pub home: String,
    pub is_executable: Arc<dyn Fn(&str) -> bool + Send + Sync>,
}

impl HostEnv {
    pub fn current() -> Self {
        Self {
            os: Os::current(),
            // `vars()` panics on a variable that is not valid Unicode; one odd variable must not stop the app.
            vars: std::env::vars_os()
                .map(|(key, value)| (key.to_string_lossy().into_owned(), value.to_string_lossy().into_owned()))
                .collect(),
            home: std::env::home_dir().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
            is_executable: Arc::new(is_executable_file),
        }
    }

    /// Windows variable names are case-insensitive ("Path" and "PATH" are the same variable).
    fn var(&self, name: &str) -> Option<&str> {
        let value = if self.os == Os::Windows {
            self.vars.iter().find(|(key, _)| key.eq_ignore_ascii_case(name)).map(|(_, v)| v)
        } else {
            self.vars.get(name)
        };
        value.map(String::as_str).filter(|v| !v.is_empty())
    }

    fn join(&self, parts: &[&str]) -> String {
        let sep = self.os.separator();
        let mut path = String::new();
        for (index, part) in parts.iter().enumerate() {
            if index == 0 {
                path.push_str(part);
                continue;
            }
            if !path.ends_with(sep) {
                path.push_str(sep);
            }
            path.push_str(part.trim_start_matches(sep));
        }
        path
    }

    /// None when the home folder is unknown, so no root-relative guess like "/Library/..." is made.
    fn default_sdk_root(&self) -> Option<String> {
        let local = self.var("LOCALAPPDATA").filter(|_| self.os == Os::Windows);
        if self.home.is_empty() && local.is_none() {
            return None;
        }
        Some(match self.os {
            Os::MacOs => self.join(&[&self.home, "Library", "Android", "sdk"]),
            Os::Linux => self.join(&[&self.home, "Android", "Sdk"]),
            Os::Windows => match local {
                Some(local) => self.join(&[local, "Android", "Sdk"]),
                None => self.join(&[&self.home, "AppData", "Local", "Android", "Sdk"]),
            },
        })
    }

    /// A GUI app does not inherit the shell PATH, so the SDK folders come before it.
    fn candidates(&self, tool: &str, sdk_subfolder: &str) -> Vec<String> {
        let file = format!("{tool}{}", self.os.exe_suffix());

        let sdk_roots = [
            self.var("ANDROID_HOME").map(String::from),
            self.var("ANDROID_SDK_ROOT").map(String::from),
            self.default_sdk_root(),
        ];
        let from_sdk = sdk_roots.into_iter().flatten().map(|root| self.join(&[&root, sdk_subfolder, &file]));

        let path_folders = split_path_list(self.var("PATH").unwrap_or(""), self.os);
        let from_path = path_folders.iter().map(|folder| self.join(&[folder, &file]));

        let fallback: &[&str] = match self.os {
            Os::MacOs => &["/opt/homebrew/bin", "/usr/local/bin"],
            Os::Linux => &["/usr/bin", "/usr/local/bin", "/snap/bin"],
            Os::Windows => &[],
        };
        let from_fallback = fallback.iter().map(|folder| self.join(&[folder, &file]));

        from_sdk.chain(from_path).chain(from_fallback).collect()
    }
}

/// Splits a PATH value. On Windows a quoted entry may itself contain ';', so quotes are honored before splitting.
fn split_path_list(value: &str, os: Os) -> Vec<String> {
    let separator = os.path_list_separator();
    let honor_quotes = os == Os::Windows;
    let (mut entries, mut current, mut in_quotes) = (Vec::new(), String::new(), false);
    for c in value.chars() {
        match c {
            '"' if honor_quotes => in_quotes = !in_quotes,
            c if c == separator && !in_quotes => entries.push(std::mem::take(&mut current)),
            c => current.push(c),
        }
    }
    entries.push(current);
    entries.into_iter().map(|e| e.trim().to_string()).filter(|e| !e.is_empty()).collect()
}

#[cfg(unix)]
fn is_executable_file(path: &str) -> bool {
    use std::os::unix::fs::PermissionsExt;
    std::fs::metadata(path).map(|m| m.is_file() && m.permissions().mode() & 0o111 != 0).unwrap_or(false)
}

#[cfg(not(unix))]
fn is_executable_file(path: &str) -> bool {
    std::fs::metadata(path).map(|m| m.is_file()).unwrap_or(false)
}

pub struct AdbService {
    runner: Arc<dyn CommandRunner>,
    env: HostEnv,
    preferred_adb: Option<String>,
}

impl Default for AdbService {
    fn default() -> Self {
        Self::new(Arc::new(ProcessRunner), HostEnv::current())
    }
}

impl AdbService {
    pub fn new(runner: Arc<dyn CommandRunner>, env: HostEnv) -> Self {
        Self { runner, env, preferred_adb: None }
    }

    /// Uses this adb (chosen in the picker) instead of looking one up; an empty path means "look it up".
    pub fn with_preferred_adb(mut self, path: &str) -> Self {
        self.preferred_adb = Some(path.trim().to_string()).filter(|p| !p.is_empty());
        self
    }

    // MARK: - Tool lookup

    pub fn adb_path(&self) -> Option<String> {
        self.preferred_adb.clone().or_else(|| self.locate("adb", "platform-tools"))
    }

    pub fn emulator_path(&self) -> Option<String> {
        self.locate("emulator", "emulator")
    }

    /// Every adb found, in lookup order, so the user can pick one when several SDKs are installed.
    pub fn adb_paths(&self) -> Vec<String> {
        let mut seen = HashSet::new();
        self.env
            .candidates("adb", "platform-tools")
            .into_iter()
            .filter(|path| (self.env.is_executable)(path))
            .filter(|path| seen.insert(self.same_file_key(path)))
            .collect()
    }

    /// Windows ignores case and treats '/' like '\\', so those spellings are one file.
    fn same_file_key(&self, path: &str) -> String {
        if self.env.os == Os::Windows {
            path.replace('/', "\\").to_lowercase()
        } else {
            path.to_string()
        }
    }

    pub fn missing_tool_message(&self) -> Option<&'static str> {
        self.adb_path().is_none().then_some(MISSING_ADB_MESSAGE)
    }

    fn locate(&self, tool: &str, sdk_subfolder: &str) -> Option<String> {
        self.env.candidates(tool, sdk_subfolder).into_iter().find(|path| (self.env.is_executable)(path))
    }

    // MARK: - Devices

    /// Running devices first, then the emulators that are installed but not started.
    pub fn list_devices(&self) -> Vec<Device> {
        let Some(adb) = self.adb_path() else { return Vec::new() };

        let result = self.runner.run_default(&adb, &["devices", "-l"]);
        if !result.succeeded() {
            eprintln!("adb devices failed: {}", result.trimmed_output());
            return Vec::new();
        }

        let running: Vec<_> = adb_parser::parse_devices(&result.output)
            .into_iter()
            .filter(|d| d.state == "device")
            .map(|d| {
                let avd_name = self.avd_name(&d.serial, &adb);
                (d, avd_name)
            })
            .collect();

        let running_names: HashSet<&str> = running.iter().filter_map(|(_, name)| name.as_deref()).collect();
        let stopped: Vec<Device> = self
            .installed_avd_names()
            .into_iter()
            .filter(|name| !running_names.contains(name.as_str()))
            .map(|name| android_device(name.clone(), format!("{AVD_PREFIX}{name}"), false))
            .collect();

        let mut devices: Vec<Device> = running
            .iter()
            .map(|(device, avd_name)| {
                let name = avd_name
                    .clone()
                    .or_else(|| device.model.as_ref().map(|m| m.replace('_', " ")))
                    .unwrap_or_else(|| device.serial.clone());
                android_device(name, device.serial.clone(), true)
            })
            .collect();
        devices.extend(stopped);
        devices
    }

    fn installed_avd_names(&self) -> Vec<String> {
        let Some(emulator) = self.emulator_path() else { return Vec::new() };
        let result = self.runner.run_default(&emulator, &["-list-avds"]);
        if result.succeeded() {
            adb_parser::parse_avd_names(&result.output)
        } else {
            Vec::new()
        }
    }

    fn avd_name(&self, serial: &str, adb: &str) -> Option<String> {
        if !serial.starts_with("emulator-") {
            return None;
        }
        let console = self.runner.run_default(adb, &["-s", serial, "emu", "avd", "name"]);
        if console.succeeded() {
            if let Some(name) = adb_parser::parse_avd_name(&console.output) {
                return Some(name);
            }
        }

        // The emulator console can be unreachable; the system property gives the same name, so a running AVD is
        // never listed a second time as stopped.
        let property = self.runner.run_default(adb, &["-s", serial, "shell", "getprop", "ro.boot.qemu.avd_name"]);
        (property.succeeded() && is_avd_name(property.trimmed_output())).then(|| property.trimmed_output().to_string())
    }

    // MARK: - Actions

    /// `package` limits the intent to one app (`am start -p`).
    pub fn open_url(&self, url: &str, serial: &str, package: Option<&str>) -> CommandResult {
        let Some(adb) = self.adb_path() else { return CommandResult::failure(MISSING_ADB_MESSAGE) };

        // `adb shell` joins its arguments and hands them to the device shell, so the URL must be quoted.
        let quoted_url = shell_quoted(url);
        let quoted_package = package.map(shell_quoted);
        let mut args = vec![
            "-s", serial, "shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d", &quoted_url,
        ];
        if let Some(package) = &quoted_package {
            args.extend(["-p", package]);
        }
        let result = self.runner.run_default(&adb, &args);

        // `am start` exits 0 even when no app handles the URL. Only a line that starts with "Error" counts,
        // because the output echoes the URL, which may itself contain that word.
        if result.succeeded() && result.output.lines().any(|line| line.starts_with("Error")) {
            return CommandResult::new(result.output, 1);
        }
        result
    }

    pub fn boot(&self, avd_name: &str) -> CommandResult {
        self.boot_with(avd_name, DEFAULT_POLL_INTERVAL, DEFAULT_BOOT_TIMEOUT)
    }

    pub fn boot_with(&self, avd_name: &str, poll_interval: Duration, timeout: Duration) -> CommandResult {
        let Some(adb) = self.adb_path() else { return CommandResult::failure(MISSING_ADB_MESSAGE) };
        let Some(emulator) = self.emulator_path() else { return CommandResult::failure(MISSING_EMULATOR_MESSAGE) };

        // An emulator that is listed but still booting must not get a second launch of the same AVD.
        match self.running_serial(avd_name, &adb) {
            Some(serial) if self.boot_completed(&serial, &adb) => {
                return CommandResult::new(format!("{avd_name} is already running"), 0);
            }
            Some(_) => {}
            None => {
                if !self.runner.launch_detached(&emulator, &["-avd", avd_name]) {
                    return CommandResult::failure(format!("Could not start emulator {avd_name}"));
                }
            }
        }

        let deadline = Instant::now() + timeout;
        while Instant::now() < deadline {
            if let Some(serial) = self.running_serial(avd_name, &adb) {
                if self.boot_completed(&serial, &adb) {
                    return CommandResult::new(format!("Booted {avd_name}"), 0);
                }
            }
            thread::sleep(poll_interval);
        }
        CommandResult::failure(format!("Timed out waiting for {avd_name} to boot"))
    }

    /// The adb serial of the running emulator that was started from this AVD.
    fn running_serial(&self, avd_name: &str, adb: &str) -> Option<String> {
        let listing = self.runner.run_default(adb, &["devices"]);
        adb_parser::parse_devices(&listing.output)
            .into_iter()
            .filter(|d| d.state == "device" && d.serial.starts_with("emulator-"))
            .find(|d| self.avd_name(&d.serial, adb).as_deref() == Some(avd_name))
            .map(|d| d.serial)
    }

    fn boot_completed(&self, serial: &str, adb: &str) -> bool {
        self.runner.run_default(adb, &["-s", serial, "shell", "getprop", "sys.boot_completed"]).trimmed_output() == "1"
    }
}

fn android_device(name: String, id: String, is_booted: bool) -> Device {
    Device { name, id, runtime: ANDROID_RUNTIME.to_string(), is_booted, kind: DeviceKind::Android }
}

/// Wraps the text in single quotes for a POSIX shell (the shell on the device, whatever the host is).
pub fn shell_quoted(text: &str) -> String {
    format!("'{}'", text.replace('\'', "'\\''"))
}

#[cfg(test)]
mod tests {
    use std::sync::atomic::{AtomicUsize, Ordering};

    use super::*;
    use crate::device::testing::{strings, FakeRunner, ADB_DEVICES};

    const ADB: &str = "/sdk/platform-tools/adb";
    const EMULATOR: &str = "/sdk/emulator/emulator";

    fn env(os: Os, vars: &[(&str, &str)], home: &str, installed: &[&str]) -> HostEnv {
        let installed: HashSet<String> = installed.iter().map(|s| s.to_string()).collect();
        HostEnv {
            os,
            vars: vars.iter().map(|(k, v)| (k.to_string(), v.to_string())).collect(),
            home: home.to_string(),
            is_executable: Arc::new(move |path| installed.contains(path)),
        }
    }

    fn service(runner: &Arc<FakeRunner>, installed: &[&str]) -> AdbService {
        AdbService::new(runner.clone(), env(Os::Linux, &[("ANDROID_HOME", "/sdk")], "/home/u", installed))
    }

    fn standard_runner() -> Arc<FakeRunner> {
        Arc::new(FakeRunner::new(|executable, args| match (executable, args) {
            (ADB, a) if a.contains(&"emu") => CommandResult::new("Pixel_8_API_35\nOK\n", 0),
            (ADB, _) => CommandResult::new("List of devices attached\nemulator-5554\tdevice model:Pixel_8\n", 0),
            (EMULATOR, _) => CommandResult::new("Pixel_8_API_35\nTablet_API_35\n", 0),
            _ => CommandResult::new("", 0),
        }))
    }

    // MARK: lookup

    #[test]
    fn finds_adb_in_android_home_before_path() {
        let env = env(Os::Linux, &[("ANDROID_HOME", "/sdk"), ("PATH", "/usr/bin")], "/home/u", &[ADB, "/usr/bin/adb"]);

        assert_eq!(AdbService::new(Arc::new(FakeRunner::silent()), env).adb_path().as_deref(), Some(ADB));
    }

    #[test]
    fn linux_falls_back_to_the_default_sdk_folder_then_path() {
        let default_sdk = env(Os::Linux, &[], "/home/u", &["/home/u/Android/Sdk/platform-tools/adb"]);
        let on_path = env(Os::Linux, &[("PATH", "/a:/b")], "/home/u", &["/b/adb"]);

        let runner = Arc::new(FakeRunner::silent());
        assert_eq!(
            AdbService::new(runner.clone(), default_sdk).adb_path().as_deref(),
            Some("/home/u/Android/Sdk/platform-tools/adb")
        );
        assert_eq!(AdbService::new(runner, on_path).adb_path().as_deref(), Some("/b/adb"));
    }

    #[test]
    fn macos_uses_library_android_sdk_and_homebrew() {
        let sdk = env(Os::MacOs, &[], "/Users/u", &["/Users/u/Library/Android/sdk/platform-tools/adb"]);
        let brew = env(Os::MacOs, &[], "/Users/u", &["/opt/homebrew/bin/adb"]);

        let runner = Arc::new(FakeRunner::silent());
        assert_eq!(
            AdbService::new(runner.clone(), sdk).adb_path().as_deref(),
            Some("/Users/u/Library/Android/sdk/platform-tools/adb")
        );
        assert_eq!(AdbService::new(runner, brew).adb_path().as_deref(), Some("/opt/homebrew/bin/adb"));
    }

    #[test]
    fn windows_uses_localappdata_exe_names_and_semicolon_paths() {
        let sdk = env(
            Os::Windows,
            &[("LOCALAPPDATA", r"C:\Users\u\AppData\Local")],
            r"C:\Users\u",
            &[r"C:\Users\u\AppData\Local\Android\Sdk\platform-tools\adb.exe"],
        );
        let on_path = env(Os::Windows, &[("Path", r"C:\Windows;C:\tools\")], r"C:\Users\u", &[r"C:\tools\adb.exe"]);

        let runner = Arc::new(FakeRunner::silent());
        assert_eq!(
            AdbService::new(runner.clone(), sdk).adb_path().as_deref(),
            Some(r"C:\Users\u\AppData\Local\Android\Sdk\platform-tools\adb.exe")
        );
        assert_eq!(AdbService::new(runner, on_path).adb_path().as_deref(), Some(r"C:\tools\adb.exe"));
    }

    #[test]
    fn windows_without_localappdata_derives_the_sdk_folder_from_home() {
        let env = env(
            Os::Windows,
            &[],
            r"C:\Users\u",
            &[r"C:\Users\u\AppData\Local\Android\Sdk\platform-tools\adb.exe"],
        );

        assert!(AdbService::new(Arc::new(FakeRunner::silent()), env).adb_path().is_some());
    }

    #[test]
    fn lists_every_adb_once_in_lookup_order() {
        let env = env(
            Os::Linux,
            &[("ANDROID_HOME", "/sdk"), ("PATH", "/sdk/platform-tools:/usr/local/bin")],
            "/home/u",
            &[ADB, "/usr/local/bin/adb"],
        );

        let paths = AdbService::new(Arc::new(FakeRunner::silent()), env).adb_paths();

        assert_eq!(paths, [ADB, "/usr/local/bin/adb"]);
    }

    #[test]
    fn a_chosen_adb_wins_over_the_lookup() {
        let runner = Arc::new(FakeRunner::silent());

        let chosen = service(&runner, &[ADB]).with_preferred_adb("/custom/adb");
        let unchosen = service(&runner, &[ADB]).with_preferred_adb("  ");

        assert_eq!(chosen.adb_path().as_deref(), Some("/custom/adb"));
        assert_eq!(unchosen.adb_path().as_deref(), Some(ADB));
    }

    #[test]
    fn explains_when_adb_is_missing_and_never_runs_anything() {
        let runner = Arc::new(FakeRunner::silent());
        let service = service(&runner, &[]);

        assert_eq!(service.missing_tool_message(), Some(MISSING_ADB_MESSAGE));
        assert!(service.list_devices().is_empty());
        assert!(!service.open_url("myapp://x", "emulator-5554", None).succeeded());
        assert!(runner.calls().is_empty());
    }

    // MARK: devices

    #[test]
    fn lists_running_emulators_first_then_stopped_avds_without_duplicates() {
        let devices = service(&standard_runner(), &[ADB, EMULATOR]).list_devices();

        let names: Vec<_> = devices.iter().map(|d| d.name.as_str()).collect();
        let ids: Vec<_> = devices.iter().map(|d| d.id.as_str()).collect();
        let booted: Vec<_> = devices.iter().map(|d| d.is_booted).collect();
        assert_eq!(names, ["Pixel_8_API_35", "Tablet_API_35"]);
        assert_eq!(ids, ["emulator-5554", "avd:Tablet_API_35"]);
        assert_eq!(booted, [true, false]);
        assert!(devices.iter().all(|d| d.kind == DeviceKind::Android));
    }

    #[test]
    fn uses_the_model_name_for_physical_devices_and_skips_offline_ones() {
        let runner = Arc::new(FakeRunner::new(|executable, args| {
            if executable == ADB && !args.contains(&"emu") {
                CommandResult::new(ADB_DEVICES, 0)
            } else {
                CommandResult::new("", 1)
            }
        }));

        let devices = service(&runner, &[ADB]).list_devices();

        assert!(devices.iter().any(|d| d.id == "R58M12345XY" && d.name == "SM G973F"));
        assert!(!devices.iter().any(|d| d.id == "emulator-5556"));
    }

    #[test]
    fn a_running_avd_whose_console_is_unreachable_is_not_listed_again_as_stopped() {
        let runner = Arc::new(FakeRunner::new(|executable, args| match (executable, args) {
            (ADB, a) if a.contains(&"emu") => CommandResult::new("KO: unauthorized", 1),
            (ADB, a) if a.contains(&"getprop") => CommandResult::new("Pixel_8_API_35\n", 0),
            (ADB, _) => CommandResult::new("List of devices attached\nemulator-5554\tdevice model:Pixel_8\n", 0),
            _ => CommandResult::new("Pixel_8_API_35\nTablet_API_35\n", 0),
        }));

        let devices = service(&runner, &[ADB, EMULATOR]).list_devices();

        let names: Vec<_> = devices.iter().map(|d| d.name.as_str()).collect();
        assert_eq!(names, ["Pixel_8_API_35", "Tablet_API_35"]);
        assert_eq!(devices.iter().map(|d| d.is_booted).collect::<Vec<_>>(), [true, false]);
    }

    // MARK: deeplink

    #[test]
    fn opens_a_deeplink_with_a_quoted_url_on_the_chosen_device() {
        let runner = Arc::new(FakeRunner::new(|_, _| CommandResult::new("Starting: Intent { }\nStatus: ok", 0)));

        let result = service(&runner, &[ADB]).open_url("myapp://x?a=1&b=it's;rm -rf /", "emulator-5554", None);

        assert!(result.succeeded());
        assert_eq!(
            runner.calls(),
            vec![strings(&[
                ADB, "-s", "emulator-5554", "shell", "am", "start", "-W", "-a", "android.intent.action.VIEW", "-d",
                "'myapp://x?a=1&b=it'\\''s;rm -rf /'",
            ])]
        );
    }

    #[test]
    fn the_package_target_is_quoted_and_passed_with_dash_p() {
        let runner = Arc::new(FakeRunner::silent());

        service(&runner, &[ADB]).open_url("myapp://x", "emulator-5554", Some("com.example"));

        let call = &runner.calls()[0];
        assert_eq!(&call[call.len() - 2..], ["-p", "'com.example'"]);
    }

    #[test]
    fn does_not_add_the_browsable_category() {
        let runner = Arc::new(FakeRunner::silent());

        service(&runner, &[ADB]).open_url("myapp://x", "emulator-5554", None);

        assert!(!runner.calls()[0].iter().any(|arg| arg.contains("BROWSABLE") || arg == "-c"));
    }

    #[test]
    fn treats_an_unresolved_intent_as_a_failure_even_though_am_exits_0() {
        let runner = Arc::new(FakeRunner::new(|_, _| {
            CommandResult::new("Error: Activity not started, unable to resolve Intent", 0)
        }));

        assert!(!service(&runner, &[ADB]).open_url("myapp://x", "emulator-5554", None).succeeded());
    }

    #[test]
    fn a_url_that_contains_the_word_error_is_not_mistaken_for_a_failure() {
        let runner = Arc::new(FakeRunner::new(|_, _| {
            CommandResult::new("Starting: Intent { dat=myapp://screen?name=ErrorPage }\nStatus: ok", 0)
        }));

        let result = service(&runner, &[ADB]).open_url("myapp://screen?name=ErrorPage", "emulator-5554", None);

        assert!(result.succeeded());
    }

    #[test]
    fn quotes_single_quotes_for_the_device_shell() {
        assert_eq!(shell_quoted("plain"), "'plain'");
        assert_eq!(shell_quoted("a'b"), "'a'\\''b'");
    }

    // MARK: boot

    #[test]
    fn boot_launches_the_emulator_and_waits_for_sys_boot_completed() {
        let device_listings = AtomicUsize::new(0);
        let boot_checks = AtomicUsize::new(0);
        let runner = Arc::new(FakeRunner::new(move |_, args| {
            if args.contains(&"emu") {
                return CommandResult::new("Pixel_8\nOK", 0);
            }
            if args.contains(&"getprop") {
                let checks = boot_checks.fetch_add(1, Ordering::SeqCst) + 1;
                return CommandResult::new(if checks < 2 { "0\n" } else { "1\n" }, 0);
            }
            // The first listing (before the launch) shows no emulator.
            if device_listings.fetch_add(1, Ordering::SeqCst) == 0 {
                return CommandResult::new("List of devices attached\n", 0);
            }
            CommandResult::new("List of devices attached\nemulator-5554\tdevice\n", 0)
        }));

        let result = service(&runner, &[ADB, EMULATOR]).boot_with("Pixel_8", Duration::ZERO, Duration::from_secs(5));

        assert!(result.succeeded(), "{}", result.output);
        assert_eq!(runner.detached_launches(), vec![strings(&[EMULATOR, "-avd", "Pixel_8"])]);
    }

    #[test]
    fn boot_does_not_start_a_second_emulator_when_it_is_already_up() {
        let runner = Arc::new(FakeRunner::new(|_, args| {
            if args.contains(&"emu") {
                CommandResult::new("Pixel_8\nOK", 0)
            } else if args.contains(&"getprop") {
                CommandResult::new("1\n", 0)
            } else {
                CommandResult::new("List of devices attached\nemulator-5554\tdevice\n", 0)
            }
        }));

        let result = service(&runner, &[ADB, EMULATOR]).boot_with("Pixel_8", Duration::ZERO, Duration::from_secs(1));

        assert!(result.succeeded());
        assert!(runner.detached_launches().is_empty());
    }

    #[test]
    fn boot_times_out_when_the_emulator_never_finishes_booting() {
        let runner = Arc::new(FakeRunner::new(|_, _| CommandResult::new("List of devices attached\n", 0)));

        let result =
            service(&runner, &[ADB, EMULATOR]).boot_with("Pixel_8", Duration::ZERO, Duration::from_millis(50));

        assert!(!result.succeeded());
        assert!(result.output.contains("Timed out"));
    }

    #[test]
    fn boot_reports_a_missing_emulator_binary() {
        let runner = Arc::new(FakeRunner::silent());

        assert_eq!(service(&runner, &[ADB]).boot("Pixel_8").output, MISSING_EMULATOR_MESSAGE);
    }

    #[test]
    fn boot_reports_when_the_emulator_cannot_be_started() {
        let mut fake = FakeRunner::new(|_, _| CommandResult::new("List of devices attached\n", 0));
        fake.launch_succeeds = false;
        let runner = Arc::new(fake);

        let result = service(&runner, &[ADB, EMULATOR]).boot("Pixel_8");

        assert!(!result.succeeded());
        assert!(result.output.contains("Could not start"));
    }

    /// Needs an Android SDK on this machine: `cargo test -- --ignored`.
    #[test]
    #[ignore]
    fn real_adb_lists_devices() {
        let service = AdbService::default();
        println!("adb: {:?}", service.adb_path());
        println!("devices: {:#?}", service.list_devices());
        assert!(service.adb_path().is_some());
    }

    #[test]
    fn boot_waits_for_an_emulator_that_is_listed_but_still_booting_without_launching_another() {
        let boot_checks = AtomicUsize::new(0);
        let runner = Arc::new(FakeRunner::new(move |_, args| {
            if args.contains(&"emu") {
                CommandResult::new("Pixel_8\nOK", 0)
            } else if args.contains(&"getprop") {
                let checks = boot_checks.fetch_add(1, Ordering::SeqCst) + 1;
                CommandResult::new(if checks < 3 { "" } else { "1\n" }, 0)
            } else {
                CommandResult::new("List of devices attached\nemulator-5554\tdevice\n", 0)
            }
        }));

        let result = service(&runner, &[ADB, EMULATOR]).boot_with("Pixel_8", Duration::ZERO, Duration::from_secs(5));

        assert!(result.succeeded(), "{}", result.output);
        assert!(runner.detached_launches().is_empty());
    }

    #[test]
    fn a_refused_console_command_that_exits_0_does_not_become_the_avd_name() {
        let runner = Arc::new(FakeRunner::new(|executable, args| match (executable, args) {
            (ADB, a) if a.contains(&"emu") => CommandResult::new("KO: unauthorized\n", 0),
            (ADB, a) if a.contains(&"getprop") => CommandResult::new("Pixel_8_API_35\n", 0),
            (ADB, _) => CommandResult::new("List of devices attached\nemulator-5554\tdevice\n", 0),
            _ => CommandResult::new("Pixel_8_API_35\n", 0),
        }));

        let devices = service(&runner, &[ADB, EMULATOR]).list_devices();

        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].name, "Pixel_8_API_35");
    }

    #[test]
    fn a_quoted_windows_path_entry_may_contain_a_semicolon() {
        let entries = split_path_list(r#"C:\a;"C:\b;c";;C:\d"#, Os::Windows);

        assert_eq!(entries, [r"C:\a", r"C:\b;c", r"C:\d"]);
        assert_eq!(split_path_list("/a::/b", Os::Linux), ["/a", "/b"]);
    }

    #[test]
    fn windows_spellings_of_one_adb_are_listed_once() {
        let env = env(
            Os::Windows,
            &[("ANDROID_HOME", r"C:\Sdk"), ("PATH", r"c:\sdk\PLATFORM-TOOLS")],
            r"C:\Users\u",
            &[r"C:\Sdk\platform-tools\adb.exe", r"c:\sdk\PLATFORM-TOOLS\adb.exe"],
        );

        assert_eq!(AdbService::new(Arc::new(FakeRunner::silent()), env).adb_paths().len(), 1);
    }

    #[test]
    fn without_a_home_folder_no_root_relative_sdk_path_is_guessed() {
        let env = env(Os::MacOs, &[], "", &["/Library/Android/sdk/platform-tools/adb"]);

        assert_eq!(AdbService::new(Arc::new(FakeRunner::silent()), env).adb_path(), None);
    }
}
