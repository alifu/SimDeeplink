use std::env;
use std::process::Command;
use std::collections::HashMap;

#[tauri::command]
pub fn fetch_adb_paths() -> Vec<String> {
    let os = std::env::consts::OS;
    let mut env_vars: HashMap<String, String> = env::vars().collect();

    // Determine Android SDK path based on OS
    let android_sdk_path = match os {
        "macos" => format!("/Users/{}/Library/Android/sdk/platform-tools", whoami::username()),
        "linux" => format!("/home/{}/Android/Sdk/platform-tools", whoami::username()),
        "windows" => format!("C:\\Users\\{}\\AppData\\Local\\Android\\Sdk\\platform-tools", whoami::username()),
        _ => String::new(),
    };

    // Build the custom PATH variable
    let custom_path = match os {
        "windows" => {
            let mut path = format!("{};C:\\Windows\\System32", android_sdk_path);
            if let Ok(existing_path) = env::var("PATH") {
                path.push(';');
                path.push_str(&existing_path);
            }
            path
        }
        _ => {
            let mut path = format!(
                "{}:/usr/local/bin:/usr/bin:/bin",
                android_sdk_path
            );
            if let Ok(existing_path) = env::var("PATH") {
                path.push(':');
                path.push_str(&existing_path);
            }
            path
        }
    };

    env_vars.insert("PATH".into(), custom_path);

    // Prepare command based on OS
    let command = if os == "windows" { "where" } else { "which" };
    let args = if os == "windows" { vec!["adb"] } else { vec!["-a", "adb"] };

    // Execute the search command
    let output = Command::new(command)
        .args(args)
        .envs(&env_vars)
        .output();

    match output {
        Ok(o) => {
            let result = String::from_utf8_lossy(&o.stdout);
            result
                .lines()
                .map(|line| line.trim().to_string())
                .filter(|s| !s.is_empty())
                .collect()
        }
        Err(e) => {
            eprintln!("Error finding adb: {}", e);
            Vec::new()
        }
    }
}

#[tauri::command]
pub fn send_deeplink(adb_path: String, package_name: String, deeplink: String) -> Result<String, String> {
    use std::process::Command;

    // Build and execute the adb command
    let output = Command::new(&adb_path)
        .args([
            "shell",
            "am",
            "start",
            "-a",
            "android.intent.action.VIEW",
            "-d",
            &deeplink,
            &package_name,
        ])
        .output();

    match output {
        Ok(o) => {
            let stdout = String::from_utf8_lossy(&o.stdout);
            let stderr = String::from_utf8_lossy(&o.stderr);

            // Combine stdout + stderr for visibility
            let combined = format!(
                ">>> STDOUT:\n{}\n>>> STDERR:\n{}",
                stdout.trim(),
                stderr.trim()
            );

            if stdout.trim().is_empty() && stderr.trim().is_empty() {
                Ok("No output received from adb. Check if emulator/device is connected.".into())
            } else {
                Ok(combined)
            }
        }
        Err(e) => Err(format!("Failed to run adb: {}", e)),
    }
}