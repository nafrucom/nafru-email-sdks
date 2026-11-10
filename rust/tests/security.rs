mod common;

use common::{Mock, client, json};
use nafru_email::*;
use serde_json::json;
use tokio::io::{AsyncReadExt, AsyncWriteExt};

fn with_base(base_url: &str) -> Result<NafruEmail> {
    NafruEmail::with_options(NafruEmailOptions {
        api_key: "nafru_secret_key".into(),
        base_url: base_url.into(),
        ..Default::default()
    })
}

fn connect_with(base_url: &str, web_url: Option<&str>) -> Result<NafruConnect> {
    NafruConnect::new(NafruConnectOptions {
        client_id: "app_x".into(),
        client_secret: "nfs_top_secret".into(),
        base_url: base_url.into(),
        web_url: web_url.map(Into::into),
        ..Default::default()
    })
}

#[test]
fn http_base_url_rejected_except_loopback() {
    for bad in [
        "http://api.example.com/api",
        "ftp://api.example.com",
        "not a url",
        "http://localhost.evil.com",
    ] {
        let error = with_base(bad).err().unwrap();
        assert_eq!(error.name, "invalid_argument", "{bad}");
        assert!(error.message.contains("https"));
    }
    for good in [
        "https://api.example.com/api",
        "http://localhost:48787/api",
        "http://app.localhost/api",
        "http://127.0.0.5:1/api",
        "http://[::1]:8080/api",
    ] {
        assert!(with_base(good).is_ok(), "{good}");
    }
    assert!(connect_with("http://api.example.com/api", None).is_err());
    assert!(
        connect_with(
            "https://api.example.com/api",
            Some("http://web.example.com")
        )
        .is_err()
    );
    assert!(connect_with("http://localhost:48787/api", None).is_ok());
}

#[tokio::test]
async fn redirect_is_an_error_and_not_retried() {
    let mock = Mock::sequence(vec![Ok(HttpResponse {
        status: 302,
        status_text: "Found".into(),
        headers: vec![("location".into(), "https://evil.example/".into())],
        body: String::new(),
    })]);
    let error = client(&mock, 2).emails.get("e1").await.unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str()),
        (Some(302), "unexpected_redirect")
    );
    assert_eq!(mock.calls().len(), 1);
}

#[tokio::test]
async fn default_transport_does_not_follow_redirects() {
    let listener = tokio::net::TcpListener::bind("127.0.0.1:0").await.unwrap();
    let port = listener.local_addr().unwrap().port();
    let server = tokio::spawn(async move {
        let mut accepted = 0;
        // Yönlendirme izlenseydi ikinci bağlantı gelirdi.
        while let Ok(Ok((mut socket, _))) =
            tokio::time::timeout(std::time::Duration::from_millis(500), listener.accept()).await
        {
            accepted += 1;
            let mut buffer = [0u8; 4096];
            let _ = socket.read(&mut buffer).await;
            let response = format!(
                "HTTP/1.1 302 Found\r\nLocation: http://127.0.0.1:{port}/elsewhere\r\nContent-Length: 0\r\nConnection: close\r\n\r\n"
            );
            socket.write_all(response.as_bytes()).await.unwrap();
        }
        accepted
    });
    let nafru = NafruEmail::with_options(NafruEmailOptions {
        api_key: "k".into(),
        base_url: format!("http://127.0.0.1:{port}/api"),
        max_retries: Some(0),
        ..Default::default()
    })
    .unwrap();
    let error = nafru.emails.get("e1").await.unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str()),
        (Some(302), "unexpected_redirect")
    );
    assert_eq!(server.await.unwrap(), 1);
}

#[tokio::test]
async fn dot_and_empty_path_segments_rejected_before_request() {
    let mock = Mock::sequence(vec![json(200, json!({}))]);
    let nafru = client(&mock, 0);
    for id in ["", ".", ".."] {
        let error = nafru.emails.get(id).await.unwrap_err();
        assert_eq!(error.name, "invalid_argument", "{id:?}");
        assert!(nafru.contacts.segments.remove("c1", id).await.is_err());
        assert!(nafru.templates.remove_translation("t1", id).await.is_err());
    }
    assert!(mock.calls().is_empty());
    // `...` ve kaçırılmış `/` geçerli kimliktir.
    let _ = nafru.emails.get("...").await;
    let _ = nafru.emails.get("a/b").await;
    let urls: Vec<_> = mock.calls().into_iter().map(|c| c.url).collect();
    assert_eq!(
        urls,
        [
            "https://api.test/emails/...",
            "https://api.test/emails/a%2Fb"
        ]
    );
}

#[tokio::test]
async fn idempotency_key_with_control_characters_rejected() {
    let mock = Mock::sequence(vec![json(200, json!({ "id": "e1" }))]);
    let nafru = client(&mock, 0);
    let input = SendEmailInput {
        to: vec!["a@b.co".into()],
        text: Some("t".into()),
        ..Default::default()
    };
    for key in ["", "k\r\nx-evil: 1", "k\n", "k\0"] {
        let error = nafru
            .emails
            .send(&input, SendEmailOptions::idempotency_key(key))
            .await
            .unwrap_err();
        assert_eq!(error.name, "invalid_argument", "{key:?}");
    }
    assert!(mock.calls().is_empty());
}

#[tokio::test]
async fn oversized_response_is_rejected() {
    let mock = Mock::sequence(vec![Ok(HttpResponse {
        status: 200,
        status_text: String::new(),
        headers: vec![],
        body: " ".repeat(10 * 1024 * 1024 + 1),
    })]);
    let error = client(&mock, 0).emails.get("e1").await.unwrap_err();
    assert_eq!(error.name, "response_too_large");
}

#[test]
fn debug_output_never_contains_secrets() {
    let nafru = with_base("https://api.example.com/api").unwrap();
    let options = NafruEmailOptions {
        api_key: "nafru_secret_key".into(),
        ..Default::default()
    };
    let connect = connect_with("https://api.example.com/api", None).unwrap();
    let connect_options = NafruConnectOptions {
        client_secret: "nfs_top_secret".into(),
        ..Default::default()
    };
    let grant = ConnectionGrant {
        connection_id: "conn_1".into(),
        refresh_token: "nfr_refresh_secret".into(),
        scopes: vec![AppScope::EmailsSend],
    };
    let tokens = ConnectionTokens {
        refresh_token: "nfr_refresh_secret".into(),
    };
    let connection_options =
        ConnectionOptions::new("nfr_refresh_secret", |_| async { Ok::<(), String>(()) });
    let connection = connect.connection("conn_1", connection_options.clone());
    let api_key = CreatedApiKey {
        id: "k1".into(),
        token: "nafru_secret_key".into(),
    };
    let request = HttpRequest {
        method: "GET",
        url: "https://api.example.com/api/emails".into(),
        headers: vec![("authorization".into(), "Bearer nafru_secret_key".into())],
        body: None,
    };
    let printed = [
        format!("{nafru:?}"),
        format!("{options:?}"),
        format!("{connect:?}"),
        format!("{connect_options:?}"),
        format!("{grant:?}"),
        format!("{tokens:?}"),
        format!("{connection_options:?}"),
        format!("{connection:?}"),
        format!("{api_key:?}"),
        format!("{request:?}"),
    ];
    for text in printed {
        for secret in ["nafru_secret_key", "nfs_top_secret", "nfr_refresh_secret"] {
            assert!(!text.contains(secret), "{text}");
        }
        assert!(
            text.contains(REDACTED) || text.starts_with("Connection"),
            "{text}"
        );
    }
    assert!(format!("{grant:?}").contains("conn_1"));
}
