//! Global shake shortcut: works from any app, shaking the booted simulator.

use tauri::{AppHandle, Manager};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};

use crate::api::service::Backend;

fn shake_shortcut() -> Shortcut {
    Shortcut::new(Some(Modifiers::SUPER | Modifiers::CONTROL | Modifiers::SHIFT), Code::KeyZ)
}

pub fn register(app_handle: &AppHandle) -> tauri::Result<()> {
    let shortcut = shake_shortcut();
    app_handle.plugin(
        tauri_plugin_global_shortcut::Builder::new()
            .with_handler(move |app, pressed, event| {
                if *pressed != shortcut || event.state() != ShortcutState::Pressed {
                    return;
                }
                let backend = app.state::<Backend>().inner().clone();
                // simctl blocks, so keep it off the thread that delivers key events.
                std::thread::spawn(move || {
                    let outcome = backend.shake(None);
                    if !outcome.ok {
                        eprintln!("Shake shortcut failed: {}", outcome.message);
                    }
                });
            })
            .build(),
    )?;
    // Another app may already own the combination; the Shake button still works then.
    if let Err(e) = app_handle.global_shortcut().register(shortcut) {
        eprintln!("Could not register the shake shortcut: {e}");
    }
    Ok(())
}
