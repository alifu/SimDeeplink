//! What the window can ask for. `service` holds the logic and is tested with a fake runner;
//! `commands` only adapts it to Tauri (async, off the UI thread).

pub mod commands;
pub mod service;
pub mod url;

pub use commands::*;
