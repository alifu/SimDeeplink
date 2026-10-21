//! Everything that depends on the host OS. Each OS exposes the same names: `init`, `show_menubar_panel`, `setup`.

#[cfg(target_os = "macos")]
mod macos;
#[cfg(target_os = "macos")]
// Glob re-export: `#[tauri::command]` also generates a hidden macro that `generate_handler!` looks up by path.
pub use macos::*;

#[cfg(not(target_os = "macos"))]
mod desktop;
#[cfg(not(target_os = "macos"))]
pub use desktop::*;
