use tauri::{
    image::Image,
    tray::{MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle,
};
use tauri_nspanel::ManagerExt;
use image::GenericImageView;
use std::{fs, process::Command};

use crate::fns::position_menubar_panel;

pub fn create(app_handle: &AppHandle) -> tauri::Result<TrayIcon> {
    // Load icon (PNG -> RGBA)
    let icon_bytes = fs::read("icons/tray-icon.png").expect("Tray icon not found");
    let dyn_img = image::load_from_memory(&icon_bytes).expect("Failed to decode image");
    let rgba = dyn_img.to_rgba8();
    let (width, height) = dyn_img.dimensions();
    let tray_icon = Image::new_owned(rgba.into_raw(), width, height);

    TrayIconBuilder::with_id("tray")
        .icon(tray_icon)
        .icon_as_template(true)
        .on_tray_icon_event(|tray, event| {
            let app_handle = tray.app_handle();

            if let TrayIconEvent::Click { button_state, .. } = event {
                if button_state == MouseButtonState::Up {
                    let panel = app_handle.get_webview_panel("main").unwrap();

                    if panel.is_visible() {
                        panel.order_out(None);
                        return;
                    }

                    position_menubar_panel(app_handle, 0.0);

                    panel.show();
                }
            }
        })
        .build(app_handle)
}