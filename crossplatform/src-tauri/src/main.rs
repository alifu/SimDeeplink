// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use simdeeplink_lib::api;
mod platform;

fn main() {
    let builder = tauri::Builder::default();

    #[cfg(target_os = "macos")]
    let builder = builder.plugin(platform::plugin());

    #[cfg(not(target_os = "macos"))]
    let builder = builder
        .plugin(tauri_plugin_positioner::init())
        // A second launch brings the first one forward instead of starting another tray icon.
        .plugin(tauri_plugin_single_instance::init(|app, _args, _cwd| platform::reveal(app)));

    builder
        .manage(api::service::Backend::system())
        .invoke_handler(tauri::generate_handler![
            platform::init,
            platform::show_menubar_panel,
            api::platforms,
            api::tool_status,
            api::adb_paths,
            api::list_devices,
            api::boot_device,
            api::open_deeplink
        ])
        .setup(|app| {
            platform::setup(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
