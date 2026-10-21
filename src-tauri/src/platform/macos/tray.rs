use tauri::{
    image::Image,
    tray::{MouseButtonState, TrayIcon, TrayIconBuilder, TrayIconEvent},
    AppHandle,
};
use tauri_nspanel::ManagerExt;
use image::GenericImageView;

const TRAY_ICON: &[u8] = include_bytes!("../../../icons/tray-icon.png");

use super::fns::position_menubar_panel;

pub fn create(app_handle: &AppHandle) -> tauri::Result<TrayIcon> {
    // Embedded in the binary: a bundled app has no "icons/" folder next to its working directory.
    let dyn_img = image::load_from_memory(TRAY_ICON).expect("Failed to decode image");
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