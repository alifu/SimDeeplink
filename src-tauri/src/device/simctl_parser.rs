use std::cmp::Ordering;
use std::collections::HashMap;

use serde::Deserialize;

use super::model::{Device, DeviceKind};

#[derive(Deserialize)]
struct DeviceList {
    devices: HashMap<String, Vec<Entry>>,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Entry {
    name: String,
    udid: String,
    state: String,
    is_available: Option<bool>,
    device_type_identifier: Option<String>,
}

#[derive(Deserialize)]
struct RuntimeList {
    runtimes: Vec<RuntimeEntry>,
}

#[derive(Deserialize)]
struct RuntimeEntry {
    identifier: String,
    name: String,
}

/// Parses `xcrun simctl list devices --json`. JSON keeps device names such as
/// "iPad Pro 13-inch (M5)" apart from the UDID, which the text output cannot.
pub fn parse(devices_json: &str, runtimes_json: Option<&str>) -> Result<Vec<Device>, serde_json::Error> {
    let list: DeviceList = serde_json::from_str(devices_json)?;
    let runtime_names = runtime_names(runtimes_json);

    // Newest runtime first.
    let mut runtime_ids: Vec<&String> = list.devices.keys().collect();
    runtime_ids.sort_by(|a, b| natural_cmp(b, a));

    Ok(runtime_ids
        .into_iter()
        .flat_map(|runtime_id| {
            let runtime = runtime_names.get(runtime_id).cloned().unwrap_or_else(|| fallback_runtime_name(runtime_id));
            list.devices[runtime_id].iter().filter(|entry| entry.is_available != Some(false)).map(move |entry| Device {
                name: entry.name.clone(),
                id: entry.udid.clone(),
                runtime: runtime.clone(),
                is_booted: entry.state == "Booted",
                kind: classify(entry.device_type_identifier.as_deref(), &entry.name),
            })
        })
        .collect())
}

pub fn classify(device_type_identifier: Option<&str>, name: &str) -> DeviceKind {
    let haystack = format!("{} {}", device_type_identifier.unwrap_or(""), name).to_lowercase();
    if haystack.contains("iphone") {
        DeviceKind::Iphone
    } else if haystack.contains("ipad") {
        DeviceKind::Ipad
    } else if haystack.contains("watch") {
        DeviceKind::Watch
    } else if haystack.contains("apple-tv") || haystack.contains("apple tv") {
        DeviceKind::Tv
    } else {
        DeviceKind::Unknown
    }
}

/// "com.apple.CoreSimulator.SimRuntime.iOS-26-0" -> "iOS 26.0"
pub fn fallback_runtime_name(identifier: &str) -> String {
    let last = identifier.rsplit('.').next().unwrap_or(identifier);
    let mut parts = last.split('-');
    let platform = parts.next().unwrap_or(identifier);
    let version: Vec<&str> = parts.collect();
    if version.is_empty() {
        platform.to_string()
    } else {
        format!("{platform} {}", version.join("."))
    }
}

fn runtime_names(json: Option<&str>) -> HashMap<String, String> {
    let Some(list) = json.and_then(|json| serde_json::from_str::<RuntimeList>(json).ok()) else {
        return HashMap::new();
    };
    let mut names = HashMap::new();
    for runtime in list.runtimes {
        names.entry(runtime.identifier).or_insert(runtime.name);
    }
    names
}

/// Compares text the way Finder does: digit runs by value, so "iOS-26-0" sorts after "iOS-18-4".
fn natural_cmp(a: &str, b: &str) -> Ordering {
    let (mut a, mut b) = (chunks(a).into_iter(), chunks(b).into_iter());
    loop {
        match (a.next(), b.next()) {
            (None, None) => return Ordering::Equal,
            (None, Some(_)) => return Ordering::Less,
            (Some(_), None) => return Ordering::Greater,
            (Some(x), Some(y)) => {
                let order = match (x.parse::<u64>(), y.parse::<u64>()) {
                    (Ok(x), Ok(y)) => x.cmp(&y),
                    _ => x.cmp(&y),
                };
                if order != Ordering::Equal {
                    return order;
                }
            }
        }
    }
}

fn chunks(text: &str) -> Vec<String> {
    let mut result: Vec<String> = Vec::new();
    for c in text.chars() {
        match result.last_mut() {
            Some(last) if last.starts_with(|f: char| f.is_ascii_digit()) == c.is_ascii_digit() => last.push(c),
            _ => result.push(c.to_string()),
        }
    }
    result
}

#[cfg(test)]
pub(crate) mod fixtures {
    pub const IPAD_PRO_13_M5: &str = "A412E5A6-62A9-478C-9935-0E1B97399786";
    pub const IPHONE_17_PRO: &str = "23F0A11F-0DD8-4766-853D-987DE9852BAC";

    /// Shaped like `xcrun simctl list devices available --json` on Xcode 26.
    pub const DEVICES: &str = r#"{"devices":{
      "com.apple.CoreSimulator.SimRuntime.iOS-18-4":[
        {"name":"iPhone 16 Pro","udid":"B0B059B3-19CB-4C5C-B677-3A9866037257","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-16-Pro"}],
      "com.apple.CoreSimulator.SimRuntime.iOS-26-0":[
        {"name":"iPhone 17 Pro","udid":"23F0A11F-0DD8-4766-853D-987DE9852BAC","state":"Booted","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro"},
        {"name":"iPad Pro 13-inch (M5)","udid":"A412E5A6-62A9-478C-9935-0E1B97399786","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Pro-13-inch-M5-8GB"},
        {"name":"iPad Air 11-inch (M3)","udid":"F4B2F269-8F69-4F7F-B2B4-CEF01C8B2D09","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPad-Air-11-inch-M3-8GB"}],
      "com.apple.CoreSimulator.SimRuntime.iOS-17-0":[
        {"name":"iPhone 15","udid":"11111111-2222-3333-4444-555555555555","state":"Shutdown","isAvailable":false,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.iPhone-15"}],
      "com.apple.CoreSimulator.SimRuntime.watchOS-26-0":[
        {"name":"Apple Watch Series 11 (46mm)","udid":"66666666-7777-8888-9999-000000000000","state":"Shutdown","isAvailable":true,"deviceTypeIdentifier":"com.apple.CoreSimulator.SimDeviceType.Apple-Watch-Series-11-46mm"}]
    }}"#;

    pub const RUNTIMES: &str = r#"{"runtimes":[
      {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-26-0","name":"iOS 26.0"},
      {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-4","name":"iOS 18.4"}]}"#;
}

#[cfg(test)]
mod tests {
    use super::fixtures::*;
    use super::*;

    fn parsed() -> Vec<Device> {
        parse(DEVICES, Some(RUNTIMES)).unwrap()
    }

    fn phones_and_tablets() -> Vec<Device> {
        parsed().into_iter().filter(|d| matches!(d.kind, DeviceKind::Iphone | DeviceKind::Ipad)).collect()
    }

    #[test]
    fn chip_names_in_parentheses_stay_part_of_the_name_never_the_udid() {
        let ipad = parsed().into_iter().find(|d| d.name == "iPad Pro 13-inch (M5)").unwrap();

        assert_eq!(ipad.id, IPAD_PRO_13_M5);
        assert_eq!(ipad.kind, DeviceKind::Ipad);
    }

    #[test]
    fn devices_sharing_a_chip_keep_distinct_ids() {
        let ids: std::collections::HashSet<_> = parsed().into_iter().map(|d| d.id).collect();

        assert_eq!(ids.len(), parsed().len());
    }

    #[test]
    fn lists_iphones_and_ipads_on_every_runtime_newest_runtime_first() {
        let devices = phones_and_tablets();

        assert_eq!(devices.first().unwrap().runtime, "iOS 26.0");
        assert_eq!(devices.iter().rfind(|d| d.kind == DeviceKind::Iphone).unwrap().runtime, "iOS 18.4");
        assert_eq!(devices.iter().filter(|d| d.kind == DeviceKind::Ipad).count(), 2);
    }

    #[test]
    fn skips_unavailable_devices() {
        assert!(!parsed().iter().any(|d| d.name == "iPhone 15"));
    }

    #[test]
    fn reads_the_booted_state() {
        let devices = parsed();

        assert!(devices.iter().find(|d| d.id == IPHONE_17_PRO).unwrap().is_booted);
        assert!(!devices.iter().find(|d| d.id == IPAD_PRO_13_M5).unwrap().is_booted);
    }

    #[test]
    fn classifies_watch_and_unknown_devices() {
        assert_eq!(parsed().iter().find(|d| d.name.contains("Watch")).unwrap().kind, DeviceKind::Watch);
        assert_eq!(classify(None, "Apple TV 4K"), DeviceKind::Tv);
        assert_eq!(classify(None, "Something"), DeviceKind::Unknown);
    }

    #[test]
    fn derives_the_runtime_name_from_its_identifier_when_the_runtime_list_is_missing() {
        let devices = parse(DEVICES, None).unwrap();

        assert_eq!(devices.iter().find(|d| d.id == IPHONE_17_PRO).unwrap().runtime, "iOS 26.0");
        assert_eq!(fallback_runtime_name("com.apple.CoreSimulator.SimRuntime.iOS-18-4"), "iOS 18.4");
    }

    #[test]
    fn fails_on_malformed_json() {
        assert!(parse("not json", None).is_err());
    }

    #[test]
    fn orders_numbers_by_value_not_by_text() {
        assert_eq!(natural_cmp("iOS-9-0", "iOS-26-0"), Ordering::Less);
        assert_eq!(natural_cmp("iOS-26-0", "iOS-26-0"), Ordering::Equal);
    }
}
