//! macOS menubar popup: an NSPanel under the status item (needs the nspanel and Cocoa crates).

mod commands;
mod fns;
mod tray;

pub use commands::*;

pub fn setup(app: &mut tauri::App) -> tauri::Result<()> {
    use tauri::Manager;

    app.set_activation_policy(tauri::ActivationPolicy::Accessory);
    tray::create(app.app_handle())?;
    Ok(())
}

/// The plugin that turns the main window into a panel.
pub fn plugin<R: tauri::Runtime>() -> tauri::plugin::TauriPlugin<R> {
    tauri_nspanel::init()
}
