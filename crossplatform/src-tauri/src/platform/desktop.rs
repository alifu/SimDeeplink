//! Windows and Linux: a tray icon that opens the window next to it, hides it when it loses focus, and a plain
//! window when the desktop has no tray (GNOME without the AppIndicator extension).

use std::sync::Mutex;
use std::time::Instant;

use tauri::{
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    AppHandle, Manager, WebviewWindow, WindowEvent,
};
use tauri_plugin_positioner::{Position, WindowExt};

use super::toggle_guard::ToggleGuard;

const TRAY_ICON: &[u8] = include_bytes!("../../icons/tray-icon.png");
const MAIN_WINDOW: &str = "main";
const MENU_OPEN: &str = "open";
const MENU_QUIT: &str = "quit";

/// Set when there is no tray: the window then stays open like a normal app.
struct NoTray;

/// The macOS build needs this call to turn the window into a panel; here there is nothing to prepare.
#[tauri::command]
pub fn init() {}

#[tauri::command]
pub fn show_menubar_panel(app_handle: AppHandle) {
    reveal(&app_handle);
}

/// Brings the window forward, for the "Open" menu entry and for a second launch of the app.
pub fn reveal(app_handle: &AppHandle) {
    let Some(window) = main_window(app_handle) else { return };
    place(&window, app_handle);
    let _ = window.show();
    let _ = window.set_focus();
}

pub fn setup(app: &mut tauri::App) -> tauri::Result<()> {
    let handle = app.handle().clone();
    app.manage(Mutex::new(ToggleGuard::default()));

    if let Some(window) = main_window(&handle) {
        watch_focus(&window, handle.clone());
    }

    match build_tray(&handle) {
        Ok(()) => {
            if let Some(window) = main_window(&handle) {
                let _ = window.set_always_on_top(true);
                let _ = window.set_skip_taskbar(true);
            }
        }
        Err(error) => {
            eprintln!("No system tray ({error}); using a normal window.");
            handle.manage(NoTray);
            use_normal_window(&handle);
        }
    }
    Ok(())
}

fn build_tray(app_handle: &AppHandle) -> tauri::Result<()> {
    let menu = Menu::with_items(
        app_handle,
        &[
            &MenuItem::with_id(app_handle, MENU_OPEN, "Open SimDeeplink", true, None::<&str>)?,
            &MenuItem::with_id(app_handle, MENU_QUIT, "Quit", true, None::<&str>)?,
        ],
    )?;

    TrayIconBuilder::with_id("tray")
        .icon(Image::from_bytes(TRAY_ICON)?)
        .tooltip("SimDeeplink")
        .menu(&menu)
        .show_menu_on_left_click(false)
        .on_menu_event(|app, event| match event.id().as_ref() {
            MENU_OPEN => reveal(app),
            MENU_QUIT => app.exit(0),
            _ => {}
        })
        .on_tray_icon_event(|tray, event| {
            // The positioner learns where the icon is from these events.
            tauri_plugin_positioner::on_tray_event(tray.app_handle(), &event);
            if let TrayIconEvent::Click { button: MouseButton::Left, button_state: MouseButtonState::Up, .. } = event {
                toggle(tray.app_handle());
            }
        })
        .build(app_handle)?;
    Ok(())
}

/// With no tray the user needs a window they can move, resize and close like any other.
fn use_normal_window(app_handle: &AppHandle) {
    let Some(window) = main_window(app_handle) else { return };
    let _ = window.set_decorations(true);
    let _ = window.set_resizable(true);
    let _ = window.set_skip_taskbar(false);
    let _ = window.set_title("SimDeeplink");
    let _ = window.center();
    let _ = window.show();
    let _ = window.set_focus();
}

fn watch_focus(window: &WebviewWindow, app_handle: AppHandle) {
    window.on_window_event(move |event| {
        // A window without a tray has no icon to reopen it from, so it must not hide itself.
        if let WindowEvent::Focused(false) = event {
            if app_handle.try_state::<NoTray>().is_none() {
                hide(&app_handle);
            }
        }
    });
}

fn hide(app_handle: &AppHandle) {
    let Some(window) = main_window(app_handle) else { return };
    if !window.is_visible().unwrap_or(false) {
        return;
    }
    let _ = window.hide();
    if let Some(guard) = app_handle.try_state::<Mutex<ToggleGuard>>() {
        if let Ok(mut guard) = guard.lock() {
            guard.note_hidden(Instant::now());
        }
    }
}

fn toggle(app_handle: &AppHandle) {
    let Some(window) = main_window(app_handle) else { return };
    if window.is_visible().unwrap_or(false) {
        hide(app_handle);
        return;
    }
    let recently_hidden = app_handle
        .try_state::<Mutex<ToggleGuard>>()
        .and_then(|guard| guard.lock().ok().map(|guard| !guard.should_show(Instant::now())))
        .unwrap_or(false);
    if !recently_hidden {
        reveal(app_handle);
    }
}

/// Anchors the window to the tray icon. Linux does not report where the icon is (and Wayland forbids
/// placing windows), so there the window opens in the middle of the screen.
fn place(window: &WebviewWindow, app_handle: &AppHandle) {
    if app_handle.try_state::<NoTray>().is_some() {
        return;
    }
    let position = if cfg!(target_os = "windows") { Position::TrayCenter } else { Position::Center };
    if window.move_window(position).is_err() {
        let _ = window.center();
    }
}

fn main_window(app_handle: &AppHandle) -> Option<WebviewWindow> {
    app_handle.get_webview_window(MAIN_WINDOW)
}
