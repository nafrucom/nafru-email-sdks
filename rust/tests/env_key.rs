mod common;

use common::{Mock, json};
use nafru_email::*;
use serde_json::json;

// Ayrı test ikilisi: ortam değişkeni başka testlerle yarışmaz.
#[tokio::test]
async fn key_omitted_reads_nafru_api_key_env() {
    // SAFETY: bu ikilide tek test var; başka iş parçacığı ortamı okumuyor.
    unsafe { std::env::set_var("NAFRU_API_KEY", "nafru_env") };
    let mock = Mock::sequence(vec![json(200, json!({ "id": "e1" }))]);
    let nafru = NafruEmail::with_options(NafruEmailOptions {
        base_url: "https://api.test".into(),
        transport: Some(mock.clone()),
        dev_outbox: DevOutbox::Off,
        ..Default::default()
    })
    .unwrap();
    nafru.emails.get("e1").await.unwrap_err();
    assert_eq!(
        mock.calls()[0].header("authorization"),
        Some("Bearer nafru_env")
    );
    assert!(NafruEmail::new("").is_ok());
}
