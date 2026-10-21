// Prevents additional console window on Windows in release, DO NOT REMOVE!!
#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod emulator;
mod platform;

fn main() {
    let builder = tauri::Builder::default();

    #[cfg(target_os = "macos")]
    let builder = builder.plugin(platform::plugin());

    builder
        .invoke_handler(tauri::generate_handler![
            platform::init,
            platform::show_menubar_panel,
            emulator::send_deeplink,
            emulator::fetch_adb_paths
        ])
        .setup(|app| {
            platform::setup(app)?;
            Ok(())
        })
        .run(tauri::generate_context!())
        .expect("error while running tauri application");
}
