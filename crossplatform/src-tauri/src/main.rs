#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use tauri::{
    menu::{Menu, MenuItemBuilder},
    tray::{TrayIconBuilder, TrayIconEvent},
    image::Image,
    Manager,
};
use std::{fs, process::Command};
use image::GenericImageView;

#[cfg(target_os = "macos")]
use cocoa::appkit::NSApp;
#[cfg(target_os = "macos")]
use objc::{msg_send, sel, sel_impl};
#[cfg(target_os = "macos")]
const nil: *mut objc::runtime::Object = std::ptr::null_mut();

#[tauri::command]
fn send_deeplink(adb_path: String, package_name: String, deeplink: String) -> Result<String, String> {
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
        Ok(o) => Ok(String::from_utf8_lossy(&o.stdout).trim().to_string()),
        Err(e) => Err(format!("Failed to execute ADB: {}", e)),
    }
}

fn main() {
    tauri::Builder::default()
        .setup(|app| {
            // macOS: hide Dock icon so app behaves like tray-only
            #[cfg(target_os = "macos")]
            unsafe {
                let ns_app = NSApp();
                // 1 == NSApplicationActivationPolicyAccessory
                let _: () = msg_send![ns_app, setActivationPolicy: 1usize];
            }

            // Build menu using the stable API that worked for you
            let menu = Menu::new(app)?;
            let quit_item = MenuItemBuilder::new("Quit SimDeeplink")
                .id("quit")
                .accelerator("CmdOrCtrl+Q")
                .build(app)?;
            menu.append(&quit_item)?;

            // Load icon (PNG -> RGBA)
            let icon_bytes = fs::read("icons/tray-icon.png").expect("Tray icon not found");
            let dyn_img = image::load_from_memory(&icon_bytes).expect("Failed to decode image");
            let rgba = dyn_img.to_rgba8();
            let (width, height) = dyn_img.dimensions();
            let tray_icon = Image::new_owned(rgba.into_raw(), width, height);

            // Build tray and attach menu + handlers
            TrayIconBuilder::new()
                .icon(tray_icon)
                .tooltip("SimDeeplink")
                .menu(&menu)
                .on_menu_event(|_tray, event| {
                    if event.id().as_ref() == "quit" {
                        println!("🧹 Quitting SimDeeplink...");
                        std::process::exit(0);
                    }
                })
                .on_tray_icon_event(|_tray, event| {
                    if let TrayIconEvent::Click { .. } = event {
                        println!("Tray icon clicked");
                    }
                })
                .build(app)?;

            Ok(())
        })
        .invoke_handler(tauri::generate_handler![send_deeplink])
        .run(tauri::generate_context!())
        .expect("error while running SimDeeplink");
}

