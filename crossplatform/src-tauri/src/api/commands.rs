use tauri::State;

use crate::device::model::{Device, Platform};

use super::service::{Backend, Outcome, ToolStatus};

/// Device tools block, so each call runs on a worker thread and never freezes the window.
async fn blocking<T: Send + 'static>(work: impl FnOnce() -> T + Send + 'static) -> Result<T, String> {
    tauri::async_runtime::spawn_blocking(work).await.map_err(|e| format!("Background task failed: {e}"))
}

#[tauri::command]
pub fn platforms(backend: State<'_, Backend>) -> Vec<Platform> {
    backend.platforms()
}

#[tauri::command]
pub async fn tool_status(backend: State<'_, Backend>, platform: Platform, adb_path: Option<String>) -> Result<ToolStatus, String> {
    let backend = backend.inner().clone();
    blocking(move || backend.tool_status(platform, adb_path.as_deref().unwrap_or_default())).await
}

#[tauri::command]
pub async fn adb_paths(backend: State<'_, Backend>) -> Result<Vec<String>, String> {
    let backend = backend.inner().clone();
    blocking(move || backend.adb_paths()).await
}

#[tauri::command]
pub async fn list_devices(backend: State<'_, Backend>, platform: Platform, adb_path: Option<String>) -> Result<Vec<Device>, String> {
    let backend = backend.inner().clone();
    blocking(move || backend.list_devices(platform, adb_path.as_deref().unwrap_or_default())).await?
}

#[tauri::command]
pub async fn boot_device(backend: State<'_, Backend>, platform: Platform, id: String, adb_path: Option<String>) -> Result<Outcome, String> {
    let backend = backend.inner().clone();
    blocking(move || backend.boot_device(platform, &id, adb_path.as_deref().unwrap_or_default())).await
}

#[tauri::command]
pub async fn open_deeplink(
    backend: State<'_, Backend>,
    platform: Platform,
    url: String,
    target: Option<String>,
    package: Option<String>,
    adb_path: Option<String>,
) -> Result<Outcome, String> {
    let backend = backend.inner().clone();
    blocking(move || {
        backend.open_deeplink(platform, &url, target.as_deref(), package.as_deref(), adb_path.as_deref().unwrap_or_default())
    })
    .await
}
