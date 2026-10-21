//! Finds devices and runs deeplinks on them. Pure Rust, no Tauri types, so `cargo test` needs no window.
//!
//! Ported from the Swift app's `Core/` folder (same behavior, same test cases):
//! tools run without a shell, output is captured with a timeout, and the device shell gets a quoted URL.

pub mod adb;
pub mod adb_parser;
pub mod model;
pub mod runner;
#[cfg(target_os = "macos")]
pub mod simctl;
#[cfg(target_os = "macos")]
pub mod simctl_parser;

#[cfg(test)]
pub(crate) mod testing;
