use serde::Serialize;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum DeviceKind {
    Iphone,
    Ipad,
    Watch,
    Tv,
    Android,
    Unknown,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum Platform {
    Ios,
    Android,
}

/// A simulator or emulator. `id` is the simulator UDID, the adb serial of a running emulator,
/// or `avd:<name>` for an emulator that is installed but not started. It stays the same between refreshes,
/// so a selection survives the list being read again.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Device {
    pub name: String,
    pub id: String,
    pub runtime: String,
    pub is_booted: bool,
    pub kind: DeviceKind,
}

impl Device {
    pub fn platform(&self) -> Platform {
        if self.kind == DeviceKind::Android {
            Platform::Android
        } else {
            Platform::Ios
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn device(kind: DeviceKind) -> Device {
        Device { name: "n".into(), id: "u".into(), runtime: "r".into(), is_booted: false, kind }
    }

    #[test]
    fn android_devices_belong_to_the_android_platform_everything_else_to_ios() {
        assert_eq!(device(DeviceKind::Android).platform(), Platform::Android);
        assert_eq!(device(DeviceKind::Ipad).platform(), Platform::Ios);
        assert_eq!(device(DeviceKind::Iphone).platform(), Platform::Ios);
    }

    #[test]
    fn serializes_with_camel_case_fields_for_the_frontend() {
        let json = serde_json::to_value(device(DeviceKind::Ipad)).unwrap();

        assert_eq!(json["isBooted"], false);
        assert_eq!(json["kind"], "ipad");
    }
}
