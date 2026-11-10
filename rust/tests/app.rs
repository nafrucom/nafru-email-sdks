mod common;

use common::{Mock, body, json};
use nafru_email::*;
use serde_json::{Value, json};
use std::sync::{Arc, Mutex};
use std::time::Duration;

fn app(mock: &Arc<Mock>) -> NafruConnect {
    NafruConnect::new(NafruConnectOptions {
        client_id: "app_x".into(),
        client_secret: "nfs_secret".into(),
        base_url: "https://api.test/".into(),
        web_url: Some("https://web.test".into()),
        transport: Some(mock.clone()),
        max_retries: Some(0),
        dev_outbox: DevOutbox::Off,
        ..Default::default()
    })
    .unwrap()
}

fn token(n: u32) -> Value {
    json!({
        "access_token": format!("nfa_{n}"),
        "refresh_token": format!("nfr_{n}"),
        "token_type": "Bearer",
        "expires_in": 3600,
        "connection_id": "conn_1",
        "scopes": ["emails.send"]
    })
}

fn status_body() -> Value {
    json!({
        "object": "connection", "id": "conn_1", "ready": true, "missing": [], "hints": [], "scopes": ["emails.send"],
        "billing_mode": "customer_pays", "setup_url": "https://web.test/setup", "workspace": { "name": "Acme" }
    })
}

fn grant_error() -> std::result::Result<HttpResponse, String> {
    json(
        400,
        json!({ "statusCode": 400, "name": "invalid_grant", "message": "invalid" }),
    )
}

fn open(nafru: &NafruConnect) -> (Connection, Arc<Mutex<Vec<String>>>) {
    let saved = Arc::new(Mutex::new(Vec::new()));
    let sink = saved.clone();
    let connection = nafru.connection(
        "conn_1",
        ConnectionOptions::new("nfr_0", move |tokens: ConnectionTokens| {
            sink.lock().unwrap().push(tokens.refresh_token);
            async { Ok::<(), String>(()) }
        }),
    );
    (connection, saved)
}

fn is_url_safe_43(text: &str) -> bool {
    text.len() == 43
        && text
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')
}

#[test]
fn pkce_and_authorize_url() {
    let (verifier, challenge) = create_pkce().unwrap();
    assert!(is_url_safe_43(&verifier) && is_url_safe_43(&challenge));
    assert_ne!(create_pkce().unwrap().0, verifier);

    let nafru = app(&Mock::new(|_| json(200, json!({}))));
    let result = nafru
        .authorize_url(&AuthorizeUrlInput {
            redirect_uri: "https://scout.test/cb".into(),
            state: "st1".into(),
            scopes: vec![AppScope::EmailsSend, AppScope::TemplatesRead],
            login_hint: Some("a@b.co".into()),
        })
        .unwrap();
    let url = url::Url::parse(&result.url).unwrap();
    assert_eq!(
        format!("{}{}", url.origin().ascii_serialization(), url.path()),
        "https://web.test/connect"
    );
    let params: std::collections::HashMap<_, _> = url.query_pairs().into_owned().collect();
    assert_eq!(params["client_id"], "app_x");
    assert_eq!(params["redirect_uri"], "https://scout.test/cb");
    assert_eq!(params["state"], "st1");
    assert_eq!(params["scope"], "emails.send templates.read");
    assert_eq!(params["code_challenge_method"], "S256");
    assert_eq!(params["login_hint"], "a@b.co");
    assert!(is_url_safe_43(&params["code_challenge"]) && is_url_safe_43(&result.code_verifier));

    let empty_state = AuthorizeUrlInput {
        redirect_uri: "x".into(),
        scopes: vec![AppScope::EmailsSend],
        ..Default::default()
    };
    assert!(nafru.authorize_url(&empty_state).is_err());
    let no_scopes = AuthorizeUrlInput {
        redirect_uri: "x".into(),
        state: "s".into(),
        ..Default::default()
    };
    assert!(nafru.authorize_url(&no_scopes).is_err());
}

#[test]
fn web_url_defaults_to_base_url_without_api() {
    let nafru = NafruConnect::new(NafruConnectOptions {
        client_id: "app_x".into(),
        client_secret: "s".into(),
        base_url: "https://email.nafru.example/api/".into(),
        ..Default::default()
    })
    .unwrap();
    let input = AuthorizeUrlInput {
        redirect_uri: "x".into(),
        state: "s".into(),
        scopes: vec![AppScope::EmailsSend],
        login_hint: None,
    };
    assert!(
        nafru
            .authorize_url(&input)
            .unwrap()
            .url
            .starts_with("https://email.nafru.example/connect?")
    );
}

#[test]
fn web_url_derives_from_default_base_url() {
    let nafru = NafruConnect::new(NafruConnectOptions {
        client_id: "app_x".into(),
        client_secret: "s".into(),
        ..Default::default()
    })
    .unwrap();
    let input = AuthorizeUrlInput {
        redirect_uri: "x".into(),
        state: "s".into(),
        scopes: vec![AppScope::EmailsSend],
        login_hint: None,
    };
    assert!(
        nafru
            .authorize_url(&input)
            .unwrap()
            .url
            .starts_with("https://email.nafru.com/connect?")
    );
}

#[tokio::test]
async fn exchange_and_revoke_send_no_authorization_header() {
    let mock = Mock::new(|_| json(200, token(1)));
    let nafru = app(&mock);
    let grant = nafru
        .exchange(&ExchangeInput {
            code: "nfc_1".into(),
            code_verifier: "v".repeat(43),
            redirect_uri: "https://scout.test/cb".into(),
        })
        .await
        .unwrap();
    assert_eq!(
        grant,
        ConnectionGrant {
            connection_id: "conn_1".into(),
            refresh_token: "nfr_1".into(),
            scopes: vec![AppScope::EmailsSend]
        }
    );
    let call = &mock.calls()[0];
    assert_eq!(
        (call.url.as_str(), call.method, call.header("authorization")),
        ("https://api.test/oauth/token", "POST", None)
    );
    let sent = body(call);
    assert_eq!(
        (
            sent["grant_type"].as_str(),
            sent["client_id"].as_str(),
            sent["client_secret"].as_str(),
            sent["code"].as_str()
        ),
        (
            Some("authorization_code"),
            Some("app_x"),
            Some("nfs_secret"),
            Some("nfc_1")
        )
    );

    nafru.revoke("nfr_1").await.unwrap();
    assert_eq!(
        body(&mock.calls()[1]),
        json!({ "client_id": "app_x", "client_secret": "nfs_secret", "token": "nfr_1" })
    );

    let error = app(&Mock::new(|_| grant_error()))
        .exchange(&ExchangeInput::default())
        .await
        .unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str()),
        (Some(400), "invalid_grant")
    );
}

#[tokio::test]
async fn first_call_refreshes_and_persists() {
    let mock = Mock::new(|req| {
        if req.url.ends_with("/oauth/token") {
            json(200, token(1))
        } else {
            json(200, status_body())
        }
    });
    let nafru = app(&mock);
    let (connection, saved) = open(&nafru);
    assert!(connection.status().await.unwrap().ready);
    assert_eq!(*saved.lock().unwrap(), ["nfr_1"]);
    let calls = mock.calls();
    assert_eq!(body(&calls[0])["grant_type"], "refresh_token");
    assert_eq!(body(&calls[0])["refresh_token"], "nfr_0");
    assert_eq!(
        (calls[1].url.as_str(), calls[1].header("authorization")),
        ("https://api.test/connection", Some("Bearer nfa_1"))
    );
}

#[tokio::test(flavor = "multi_thread", worker_threads = 4)]
async fn concurrent_calls_share_a_single_refresh() {
    let mock = Mock::with_delay(Duration::from_millis(20), |req| {
        if req.url.ends_with("/oauth/token") {
            json(200, token(1))
        } else {
            json(200, status_body())
        }
    });
    let nafru = app(&mock);
    let (connection, saved) = open(&nafru);
    let handles: Vec<_> = (0..5)
        .map(|_| {
            let connection = connection.clone();
            tokio::spawn(async move { connection.status().await })
        })
        .collect();
    for handle in handles {
        handle.await.unwrap().unwrap();
    }
    assert_eq!(mock.count("/oauth/token"), 1);
    assert_eq!(*saved.lock().unwrap(), ["nfr_1"]);
    connection.status().await.unwrap();
    assert_eq!(mock.count("/oauth/token"), 1);
}

#[tokio::test]
async fn invalid_token_refreshes_once_and_retries_with_rotated_token() {
    let refreshes = Arc::new(Mutex::new(0));
    let counter = refreshes.clone();
    let mock = Mock::new(move |req| {
        if req.url.ends_with("/oauth/token") {
            let mut n = counter.lock().unwrap();
            *n += 1;
            return json(200, token(*n));
        }
        if req.header("authorization") == Some("Bearer nfa_1") {
            json(
                401,
                json!({ "statusCode": 401, "name": "invalid_token", "message": "expired" }),
            )
        } else {
            json(200, status_body())
        }
    });
    let nafru = app(&mock);
    let (connection, saved) = open(&nafru);
    connection.status().await.unwrap();
    assert_eq!(*refreshes.lock().unwrap(), 2);
    assert_eq!(*saved.lock().unwrap(), ["nfr_1", "nfr_2"]);
    let refresh_bodies: Vec<_> = mock
        .calls()
        .iter()
        .filter(|c| c.url.ends_with("/oauth/token"))
        .map(|c| body(c)["refresh_token"].clone())
        .collect();
    assert_eq!(refresh_bodies, [json!("nfr_0"), json!("nfr_1")]);
    let auths: Vec<_> = mock
        .calls()
        .iter()
        .filter(|c| !c.url.contains("/oauth/"))
        .map(|c| c.header("authorization").map(str::to_owned))
        .collect();
    assert_eq!(
        auths,
        [Some("Bearer nfa_1".into()), Some("Bearer nfa_2".into())]
    );
}

#[tokio::test]
async fn rejected_refresh_is_connection_revoked() {
    let mock = Mock::new(|_| grant_error());
    let (connection, _) = open(&app(&mock));
    assert_eq!(
        connection.status().await.unwrap_err().name,
        "connection_revoked"
    );
    assert_eq!(
        mock.calls()
            .iter()
            .filter(|c| !c.url.contains("/oauth/"))
            .count(),
        0
    );

    let forbidden = Mock::new(|_| {
        json(
            403,
            json!({ "statusCode": 403, "name": "forbidden", "message": "no" }),
        )
    });
    let (connection, _) = open(&app(&forbidden));
    assert_eq!(
        connection.status().await.unwrap_err().name,
        "connection_revoked"
    );
}

#[tokio::test]
async fn persist_failure_is_reported_then_retried_without_new_refresh() {
    let mock = Mock::new(|req| {
        if req.url.ends_with("/oauth/token") {
            json(200, token(1))
        } else {
            json(200, status_body())
        }
    });
    let nafru = app(&mock);
    let saved = Arc::new(Mutex::new(Vec::new()));
    let failures = Arc::new(Mutex::new(1));
    let (sink, left) = (saved.clone(), failures.clone());
    let connection = nafru.connection(
        "conn_1",
        ConnectionOptions::new("nfr_0", move |tokens: ConnectionTokens| {
            let mut left = left.lock().unwrap();
            let result = if *left > 0 {
                *left -= 1;
                Err("disk dolu")
            } else {
                sink.lock().unwrap().push(tokens.refresh_token);
                Ok(())
            };
            async move { result }
        }),
    );
    let error = connection.status().await.unwrap_err();
    assert_eq!(error.name, "token_persist_failed");
    assert!(error.message.contains("disk dolu"));
    connection.status().await.unwrap();
    assert_eq!(*saved.lock().unwrap(), ["nfr_1"]);
    assert_eq!(mock.count("/oauth/token"), 1);
}

#[tokio::test]
async fn connection_endpoints() {
    let mock = Mock::new(|req| {
        let path = req.url.trim_start_matches("https://api.test");
        match (req.method, path) {
            (_, "/oauth/token") => json(200, token(1)),
            ("GET", "/senders") => json(
                200,
                json!({ "domains": [{ "id": "d1", "name": "acme.test" }], "default_from": null }),
            ),
            ("POST", "/emails") => json(200, json!({ "id": "e1" })),
            _ => json(
                200,
                json!({ "object": "list", "data": [], "has_more": false }),
            ),
        }
    });
    let nafru = app(&mock);
    let (connection, _) = open(&nafru);
    assert_eq!(connection.id, "conn_1");
    connection.senders.list().await.unwrap();
    connection.templates.list().await.unwrap();
    let input = SendEmailInput {
        from: Some("a@b.co".into()),
        to: vec!["c@d.co".into()],
        subject: Some("s".into()),
        html: Some("<p>x</p>".into()),
        ..Default::default()
    };
    connection
        .emails
        .send(&input, SendEmailOptions::idempotency_key("k1"))
        .await
        .unwrap();
    let _ = connection.emails.get("e1").await;
    connection.emails.list(Default::default()).await.unwrap();
    let routes: Vec<_> = mock
        .calls()
        .iter()
        .filter(|c| !c.url.contains("/oauth/"))
        .map(|c| {
            format!(
                "{} {}",
                c.method,
                c.url.trim_start_matches("https://api.test")
            )
        })
        .collect();
    assert_eq!(
        routes,
        [
            "GET /senders",
            "GET /templates",
            "POST /emails",
            "GET /emails/e1",
            "GET /emails"
        ]
    );

    let scope = Mock::new(|req| {
        if req.url.ends_with("/oauth/token") {
            json(200, token(1))
        } else {
            json(
                403,
                json!({ "statusCode": 403, "name": "insufficient_scope", "message": "scope" }),
            )
        }
    });
    let (connection, _) = open(&app(&scope));
    let error = connection.templates.list().await.unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str()),
        (Some(403), "insufficient_scope")
    );
}
