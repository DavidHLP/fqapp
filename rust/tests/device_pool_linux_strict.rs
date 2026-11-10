//! Production-policy regressions run in an isolated process and synthetic files.
#![cfg(target_os = "linux")]
mod common;
use common::{pool_json, TempDir};
use fqapi_core::device::{pool_crypto, DevicePool};

#[tokio::test]
async fn production_requires_key_and_preserves_wrong_key_file() {
    if let Some(path) = std::env::var_os("FQAPP_SYNTHETIC_POOL_READBACK") {
        pool_crypto::provision_pool_key(vec![0x11; 32]).unwrap();
        assert_eq!(
            DevicePool::for_runtime(path).await.unwrap().count().await,
            2
        );
        return;
    }
    let dir = TempDir::new("linux-strict");
    let path = dir.join("pool.json");
    dir.write("pool.json", &pool_json(2));
    let plain = std::fs::read(&path).unwrap();
    assert!(DevicePool::for_runtime(&path).await.is_err());
    assert_eq!(std::fs::read(&path).unwrap(), plain);
    let missing = dir.join("missing.json");
    assert!(DevicePool::for_runtime(&missing).await.is_err());
    assert!(!missing.exists());
    pool_crypto::provision_pool_key(vec![0x11; 32]).unwrap();
    let pool = DevicePool::for_runtime(&path).await.unwrap();
    pool.refill(0).await.unwrap();
    let encrypted = std::fs::read(&path).unwrap();
    assert!(pool_crypto::pool_file_is_encrypted(&encrypted));
    assert_eq!(
        DevicePool::for_runtime(&path).await.unwrap().count().await,
        2
    );
    let readback = std::process::Command::new(std::env::current_exe().unwrap())
        .args([
            "--exact",
            "production_requires_key_and_preserves_wrong_key_file",
        ])
        .env("FQAPP_SYNTHETIC_POOL_READBACK", &path)
        .status()
        .unwrap();
    assert!(readback.success());
    pool_crypto::provision_pool_key(vec![0x22; 32]).unwrap();
    assert!(DevicePool::for_runtime(&path).await.is_err());
    assert!(pool.refill(0).await.is_err());
    assert_eq!(std::fs::read(&path).unwrap(), encrypted);
    assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
}
