mod common;

use common::Mock;
use nafru_email::*;
use std::path::PathBuf;

#[tokio::test]
async fn writes_txt_and_html_instead_of_sending() {
    let dir: PathBuf = std::env::temp_dir().join(format!("nafru-outbox-{}", std::process::id()));
    let _ = std::fs::remove_dir_all(&dir);
    let mock = Mock::new(|_| Err("taşıyıcı çağrılmamalı".into()));
    let nafru = NafruEmail::with_options(NafruEmailOptions {
        transport: Some(mock.clone()),
        dev_outbox: DevOutbox::Dir(dir.clone()),
        base_url: "https://api.test".into(),
        api_key: "k".into(),
        ..Default::default()
    })
    .unwrap();

    let sent = nafru
        .emails
        .send(
            &SendEmailInput {
                from: Some("a@x.com".into()),
                to: vec!["b@y.com".into(), "c@y.com".into()],
                subject: Some("Merhaba".into()),
                html: Some("<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>".into()),
                ..Default::default()
            },
            Default::default(),
        )
        .await
        .unwrap();
    let batch = nafru
        .emails
        .batch(
            &[BatchEmailItem {
                from: "a@x.com".into(),
                to: vec!["d@y.com".into()],
                subject: "S".into(),
                text: Some("düz".into()),
                ..Default::default()
            }],
            Default::default(),
        )
        .await
        .unwrap();

    assert!(sent.id.starts_with("dev_"));
    assert_eq!(batch.data.len(), 1);
    assert!(mock.calls().is_empty());
    let files: Vec<String> = std::fs::read_dir(&dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .collect();
    assert_eq!(files.iter().filter(|f| f.ends_with(".txt")).count(), 2);
    assert_eq!(files.iter().filter(|f| f.ends_with(".html")).count(), 2);
    let find = |ext: &str| {
        dir.join(
            files
                .iter()
                .find(|f| f.contains(&sent.id) && f.ends_with(ext))
                .unwrap(),
        )
    };
    let txt = std::fs::read_to_string(find(".txt")).unwrap();
    assert!(txt.contains("To: b@y.com, c@y.com"));
    assert!(txt.contains("Subject: Merhaba"));
    assert!(txt.contains("Selam Ali\n& hoş geldin"));
    assert!(
        std::fs::read_to_string(find(".html"))
            .unwrap()
            .contains("<b>Ali</b>")
    );
    std::fs::remove_dir_all(&dir).unwrap();
}
