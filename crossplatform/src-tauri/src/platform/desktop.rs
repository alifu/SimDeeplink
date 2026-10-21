//! Windows and Linux: a tray icon that shows and hides the main window.
//! (Positioning near the tray and the Linux no-tray fallback come in a later phase.)

use tauri::{
    image::Image,
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager,
};

const TRAY_ICON: &[u8] = include_bytes!("../../icons/tray-icon.png");

/// The macOS build needs this call to turn the window into a panel; here there is nothing to prepare.
#[tauri::command]
pub fn init() {}

#[tauri::command]
pub fn show_menubar_panel(app_handle: AppHandle) {
    show_main_window(&app_handle);
}

pub fn setup(app: &mut tauri::App) -> tauri::Result<()> {
    let icon = Image::from_bytes(TRAY_ICON)?;

    TrayIconBuilder::with_id("tray")
        .icon(icon)
        .on_tray_icon_event(|tray, event| {
            if let TrayIconEvent::Click {
                button: MouseButton::Left,
                button_state: MouseButtonState::Up,
                ..
            } = event
            {
                toggle_main_window(tray.app_handle());
            }
        })
        .build(app)?;
    Ok(())
}

fn toggle_main_window(app_handle: &AppHandle) {
    let Some(window) = app_handle.get_webview_window("main") else {
        return;
    };
    if window.is_visible().unwrap_or(false) {
        let _ = window.hide();
    } else {
        show_main_window(app_handle);
    }
}

fn show_main_window(app_handle: &AppHandle) {
    if let Some(window) = app_handle.get_webview_window("main") {
        let _ = window.show();
        let _ = window.set_focus();
    }
}
