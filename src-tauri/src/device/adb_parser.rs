#[derive(Debug, Clone, PartialEq, Eq)]
pub struct AdbDevice {
    pub serial: String,
    pub state: String,
    pub model: Option<String>,
}

const KNOWN_STATES: [&str; 9] =
    ["device", "offline", "unauthorized", "authorizing", "recovery", "sideload", "bootloader", "host", "no"];

/// Parses `adb devices -l`; daemon notices and other noise are skipped.
pub fn parse_devices(output: &str) -> Vec<AdbDevice> {
    output
        .lines()
        .filter_map(|line| {
            let text = line.trim();
            if text.is_empty() || text.starts_with('*') || text.starts_with("List of devices") {
                return None;
            }
            let fields: Vec<&str> = text.split_whitespace().collect();
            if fields.len() < 2 || !KNOWN_STATES.contains(&fields[1]) {
                return None;
            }
            let model = fields[2..].iter().find_map(|field| field.strip_prefix("model:")).map(String::from);
            Some(AdbDevice { serial: fields[0].to_string(), state: fields[1].to_string(), model })
        })
        .collect()
}

/// Parses `emulator -list-avds`, ignoring "INFO |" style log lines.
pub fn parse_avd_names(output: &str) -> Vec<String> {
    output.lines().map(str::trim).filter(|line| is_avd_name(line)).map(String::from).collect()
}

/// Parses `adb -s <serial> emu avd name`, which prints the name and then "OK".
pub fn parse_avd_name(emu_output: &str) -> Option<String> {
    // The console can refuse the command and still exit 0 ("KO: ..."); only a real AVD name counts.
    emu_output.lines().map(str::trim).find(|line| is_avd_name(line) && *line != "OK").map(String::from)
}

pub fn is_avd_name(text: &str) -> bool {
    !text.is_empty() && text.chars().all(|c| c.is_ascii_alphanumeric() || matches!(c, '.' | '_' | '-'))
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::device::testing::ADB_DEVICES;

    #[test]
    fn parses_devices_and_skips_daemon_notices() {
        let devices = parse_devices(ADB_DEVICES);

        let serials: Vec<_> = devices.iter().map(|d| d.serial.as_str()).collect();
        let states: Vec<_> = devices.iter().map(|d| d.state.as_str()).collect();
        assert_eq!(serials, ["emulator-5554", "emulator-5556", "R58M12345XY"]);
        assert_eq!(states, ["device", "offline", "device"]);
        assert_eq!(devices[0].model.as_deref(), Some("sdk_gphone64_arm64"));
        assert_eq!(devices[1].model, None);
    }

    #[test]
    fn ignores_version_mismatch_noise_and_blank_output() {
        let noise = "adb server version (41) doesn't match this client (40); killing...\n";

        assert!(parse_devices(noise).is_empty());
        assert!(parse_devices("").is_empty());
    }

    #[test]
    fn parses_windows_line_endings() {
        let devices = parse_devices("List of devices attached\r\nemulator-5554\tdevice model:Pixel_8\r\n\r\n");

        assert_eq!(devices.len(), 1);
        assert_eq!(devices[0].model.as_deref(), Some("Pixel_8"));
    }

    #[test]
    fn parses_avd_names_and_drops_log_lines() {
        let output = "INFO    | Storing crashdata\nPixel_8_API_35\nMedium_Phone.API-36\n\n";

        assert_eq!(parse_avd_names(output), ["Pixel_8_API_35", "Medium_Phone.API-36"]);
    }

    #[test]
    fn reads_the_avd_name_before_ok() {
        assert_eq!(parse_avd_name("Pixel_8_API_35\r\nOK\r\n").as_deref(), Some("Pixel_8_API_35"));
        assert_eq!(parse_avd_name("OK\n"), None);
        assert_eq!(parse_avd_name("KO: unauthorized\n"), None);
    }
}
