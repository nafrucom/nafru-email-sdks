mod common;

use common::{Mock, body, client, json, json_with};
use nafru_email::*;
use serde_json::json;
use std::sync::Arc;
use std::time::Duration;

fn email() -> SendEmailInput {
    SendEmailInput {
        from: Some("a@x.test".into()),
        to: vec!["b@x.test".into()],
        subject: Some("s".into()),
        text: Some("t".into()),
        ..Default::default()
    }
}

#[tokio::test]
async fn send_sets_auth_user_agent_json_and_idempotency_key() {
    let mock = Mock::sequence(vec![json(200, json!({ "id": "e1" }))]);
    let nafru = client(&mock, 0);
    let sent = nafru
        .emails
        .send(&email(), SendEmailOptions::idempotency_key("k-1"))
        .await
        .unwrap();
    assert_eq!(sent.id, "e1");
    let call = &mock.calls()[0];
    assert_eq!(call.url, "https://api.test/emails");
    assert_eq!(call.method, "POST");
    assert_eq!(call.header("authorization"), Some("Bearer key_test"));
    assert_eq!(call.header("content-type"), Some("application/json"));
    assert_eq!(call.header("idempotency-key"), Some("k-1"));
    assert_eq!(
        call.header("user-agent"),
        Some(format!("nafru-email-rust/{SDK_VERSION}").as_str())
    );
    assert_eq!(
        body(call),
        json!({ "from": "a@x.test", "to": ["b@x.test"], "subject": "s", "text": "t" })
    );
}

#[tokio::test]
async fn query_skips_empty_values_and_path_is_encoded() {
    let mock = Mock::sequence(vec![json(
        200,
        json!({ "object": "list", "data": [], "has_more": false }),
    )]);
    let nafru = client(&mock, 0);
    nafru
        .contacts
        .list(ListContactsQuery {
            limit: Some(5),
            search: Some("ali veli".into()),
            before: Some(String::new()),
            ..Default::default()
        })
        .await
        .unwrap();
    assert_eq!(
        mock.calls()[0].url,
        "https://api.test/contacts?limit=5&search=ali+veli"
    );

    let _ = nafru.contacts.get("a+b@x.com").await;
    assert_eq!(
        mock.calls()[1].url,
        "https://api.test/contacts/a%2Bb%40x.com"
    );
}

#[tokio::test]
async fn error_body_is_parsed() {
    let body = json!({
        "statusCode": 422,
        "name": "validation_error",
        "message": "Geçersiz",
        "errors": [{ "field": "to", "message": "zorunlu", "i18nTranslationKey": "k" }]
    });
    let mock = Mock::sequence(vec![json(422, body)]);
    let error = client(&mock, 0)
        .emails
        .send(&email(), Default::default())
        .await
        .unwrap_err();
    assert_eq!(error.status_code, Some(422));
    assert_eq!(error.name, "validation_error");
    assert_eq!(error.message, "Geçersiz");
    assert_eq!(
        error.errors,
        vec![NafruFieldError {
            field: "to".into(),
            message: "zorunlu".into(),
            i18n_translation_key: Some("k".into())
        }]
    );
}

#[tokio::test]
async fn non_standard_body_falls_back_to_status() {
    let mock = Mock::sequence(vec![Ok(HttpResponse {
        status: 502,
        status_text: "Bad Gateway".into(),
        headers: vec![],
        body: "<html>bad gateway</html>".into(),
    })]);
    let error = client(&mock, 0).emails.get("e1").await.unwrap_err();
    assert_eq!(
        (
            error.status_code,
            error.name.as_str(),
            error.message.as_str()
        ),
        (Some(502), "application_error", "Bad Gateway")
    );

    let mock = Mock::sequence(vec![json(404, json!(null))]);
    let error = client(&mock, 0).emails.get("e1").await.unwrap_err();
    assert_eq!(
        (error.name.as_str(), error.message.as_str()),
        ("not_found", "HTTP 404")
    );
}

#[tokio::test]
async fn network_error_has_no_status() {
    let mock = Mock::sequence(vec![Err("fetch failed".into())]);
    let error = client(&mock, 0)
        .emails
        .send(&email(), Default::default())
        .await
        .unwrap_err();
    assert_eq!(
        error,
        NafruError {
            status_code: None,
            name: "application_error".into(),
            message: "fetch failed".into(),
            errors: vec![],
            retry_after: None
        }
    );
}

fn limited() -> std::result::Result<HttpResponse, String> {
    json_with(
        429,
        json!({ "statusCode": 429, "name": "rate_limit_exceeded", "message": "yavaş" }),
        &[("Retry-After", "0")],
    )
}

#[tokio::test]
async fn post_429_is_retried_with_retry_after() {
    let mock = Mock::sequence(vec![limited(), json(200, json!({ "id": "e1" }))]);
    let sent = client(&mock, 2)
        .emails
        .send(&email(), Default::default())
        .await
        .unwrap();
    assert_eq!(sent.id, "e1");
    assert_eq!(mock.calls().len(), 2);
}

#[tokio::test]
async fn exhausted_429_returns_retry_after() {
    let mock = Mock::sequence(vec![limited()]);
    let error = client(&mock, 1).emails.get("e1").await.unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str(), error.retry_after),
        (Some(429), "rate_limit_exceeded", Some(0))
    );
    assert_eq!(mock.calls().len(), 2);
}

fn down() -> std::result::Result<HttpResponse, String> {
    json(
        500,
        json!({ "statusCode": 500, "name": "application_error", "message": "x" }),
    )
}

#[tokio::test]
async fn get_5xx_retried_but_post_without_key_is_not() {
    let mock = Mock::sequence(vec![down(), json(200, json!({ "id": "e1" }))]);
    let result = client(&mock, 1)
        .emails
        .send(&email(), Default::default())
        .await;
    assert_eq!(result.unwrap_err().status_code, Some(500));
    assert_eq!(mock.calls().len(), 1);

    let mock = Mock::sequence(vec![
        down(),
        json(
            200,
            json!({ "object": "domain", "id": "d1", "deleted": true }),
        ),
    ]);
    assert!(client(&mock, 1).domains.remove("d1").await.unwrap().deleted);
    assert_eq!(mock.calls().len(), 2);
}

#[tokio::test]
async fn post_with_idempotency_key_retried_after_5xx() {
    let mock = Mock::sequence(vec![down(), json(200, json!({ "id": "e1" }))]);
    let sent = client(&mock, 1)
        .emails
        .send(&email(), SendEmailOptions::idempotency_key("k-1"))
        .await
        .unwrap();
    assert_eq!(sent.id, "e1");
    let calls = mock.calls();
    assert_eq!(calls.len(), 2);
    assert_eq!(calls[1].header("idempotency-key"), Some("k-1"));
}

struct Hang;

impl Transport for Hang {
    fn send(&self, _: HttpRequest) -> BoxFuture<'_, std::result::Result<HttpResponse, String>> {
        Box::pin(std::future::pending())
    }
}

#[tokio::test]
async fn timeout_returns_timeout_error() {
    let nafru = NafruEmail::with_options(NafruEmailOptions {
        transport: Some(Arc::new(Hang)),
        max_retries: Some(0),
        timeout: Some(Duration::from_millis(20)),
        base_url: "https://api.test".into(),
        api_key: "k".into(),
        ..Default::default()
    })
    .unwrap();
    let error = nafru.emails.get("e1").await.unwrap_err();
    assert_eq!(
        (error.status_code, error.name.as_str()),
        (None, "timeout_error")
    );
}

#[test]
fn api_key_required() {
    // Ortamda anahtar varsa boş anahtar ondan okunur; bu durum tests/env_key.rs'te denetlenir.
    if std::env::var_os("NAFRU_API_KEY").is_some() {
        return;
    }
    assert!(
        NafruEmail::new("")
            .err()
            .unwrap()
            .message
            .contains("apiKey")
    );
}

#[tokio::test]
async fn base_url_defaults_to_production() {
    let mock = Mock::sequence(vec![json(200, json!({ "id": "e1" }))]);
    let nafru = NafruEmail::with_options(NafruEmailOptions {
        transport: Some(mock.clone()),
        dev_outbox: DevOutbox::Off,
        api_key: "k".into(),
        ..Default::default()
    })
    .unwrap();
    nafru
        .emails
        .send(&email(), Default::default())
        .await
        .unwrap();
    assert_eq!(mock.calls()[0].url, format!("{DEFAULT_BASE_URL}/emails"));
    assert_eq!(DEFAULT_BASE_URL, "https://email.nafru.com/api");
}

#[tokio::test]
async fn contacts_topics_update_sends_bare_array() {
    let mock = Mock::sequence(vec![json(200, json!({ "object": "contact", "id": "c1" }))]);
    let input = UpdateContactTopicsInput {
        topics: vec![SubscriptionRef {
            id: "t1".into(),
            subscription: TopicSubscription::OptOut,
        }],
    };
    client(&mock, 0)
        .contacts
        .topics
        .update("a@b.co", &input)
        .await
        .unwrap();
    let call = &mock.calls()[0];
    assert_eq!(
        (call.method, call.url.as_str()),
        ("PATCH", "https://api.test/contacts/a%40b.co/topics")
    );
    assert_eq!(
        body(call),
        json!([{ "id": "t1", "subscription": "opt_out" }])
    );
}

#[tokio::test]
async fn nullable_fields_send_null_only_when_set() {
    let mock = Mock::sequence(vec![json(200, json!({ "object": "contact", "id": "c1" }))]);
    let input = UpdateContactInput {
        first_name: Some(None),
        unsubscribed: Some(true),
        ..Default::default()
    };
    client(&mock, 0)
        .contacts
        .update("c1", &input)
        .await
        .unwrap();
    assert_eq!(
        body(&mock.calls()[0]),
        json!({ "first_name": null, "unsubscribed": true })
    );
}

#[tokio::test]
async fn deprecation_header_never_fails_the_call() {
    let headers = [
        ("Deprecation", "true"),
        ("Sunset", "Wed, 01 Jul 2027 00:00:00 GMT"),
    ];
    let mock = Mock::sequence(vec![json_with(200, json!({ "id": "e1" }), &headers)]);
    let nafru = client(&mock, 0);
    assert_eq!(
        nafru
            .emails
            .send(&email(), Default::default())
            .await
            .unwrap()
            .id,
        "e1"
    );
    assert_eq!(
        nafru
            .emails
            .send(&email(), Default::default())
            .await
            .unwrap()
            .id,
        "e1"
    );
}

#[tokio::test]
async fn paginate_follows_after_cursor_and_surfaces_errors() {
    let contact = |id: &str| json!({ "id": id, "email": format!("{id}@x.co"), "first_name": null, "last_name": null, "unsubscribed": false, "locale": null, "created_at": "2026-01-01" });
    let mock = Mock::sequence(vec![
        json(
            200,
            json!({ "object": "list", "data": [contact("c1"), contact("c2")], "has_more": true }),
        ),
        json(
            200,
            json!({ "object": "list", "data": [contact("c3")], "has_more": false }),
        ),
    ]);
    let nafru = client(&mock, 0);
    let all = paginate(
        |q| nafru.contacts.list(q),
        ListContactsQuery {
            limit: Some(2),
            ..Default::default()
        },
    )
    .collect()
    .await
    .unwrap();
    assert_eq!(
        all.iter().map(|c| c.id.as_str()).collect::<Vec<_>>(),
        ["c1", "c2", "c3"]
    );
    let urls: Vec<_> = mock.calls().into_iter().map(|c| c.url).collect();
    assert_eq!(
        urls,
        [
            "https://api.test/contacts?limit=2",
            "https://api.test/contacts?after=c2&limit=2"
        ]
    );

    let mock = Mock::sequence(vec![json(
        500,
        json!({ "statusCode": 500, "name": "application_error", "message": "x" }),
    )]);
    let nafru = client(&mock, 0);
    let mut pages = paginate(|q| nafru.domains.list(q), ListQuery::default());
    assert_eq!(pages.next().await.unwrap_err().status_code, Some(500));
}

#[tokio::test]
async fn broadcast_recurrence_and_data_source_round_trip() {
    let detail = json!({
        "object": "broadcast", "id": "b1", "name": "Haftalık", "segment_id": "s1", "audience_id": "s1", "subject": "S",
        "status": "draft", "created_at": "2026-01-01", "scheduled_at": null, "sent_at": null,
        "recurrence": { "type": "weekly", "days": [1, 3], "time": "09:30" },
        "trigger_state": "active", "next_run_at": "2026-01-05T09:30:00Z", "parent_id": null,
        "from": "a@x.co", "reply_to": null, "preview_text": null, "topic_id": null, "template_id": "welcome",
        "html": null, "text": null, "open_tracking": true, "click_tracking": false, "finished_at": null, "failure_reason": null,
        "data": { "plan": "pro" },
        "data_source": { "type": "url", "url": "https://x.co/d.json", "header_name": "X-Key", "has_header_value": true }
    });
    let mut unknown = detail.clone();
    unknown["recurrence"] = json!({ "type": "hourly", "every_hours": 2 });
    unknown["data_source"] = json!({ "type": "s3", "bucket": "b" });
    let mock = Mock::sequence(vec![
        json(200, detail),
        json(200, unknown),
        json(200, json!({ "object": "broadcast", "id": "b2" })),
    ]);
    let nafru = client(&mock, 0);

    let broadcast = nafru.broadcasts.get("b1").await.unwrap();
    assert_eq!(
        broadcast.item.recurrence,
        Some(BroadcastRecurrence::Weekly {
            days: vec![1, 3],
            time: "09:30".into()
        })
    );
    assert_eq!(
        broadcast.item.trigger_state,
        Some(BroadcastTriggerState::Active)
    );
    assert_eq!(
        broadcast.data_source,
        Some(BroadcastDataSource::Url {
            url: "https://x.co/d.json".into(),
            header_name: Some("X-Key".into()),
            has_header_value: true
        })
    );
    assert_eq!(broadcast.data.unwrap()["plan"], "pro");

    let broadcast = nafru.broadcasts.get("b1").await.unwrap();
    assert_eq!(
        broadcast.item.recurrence,
        Some(BroadcastRecurrence::Unknown)
    );
    assert_eq!(broadcast.data_source, Some(BroadcastDataSource::Unknown));

    let input = CreateBroadcastInput {
        segment_id: "s1".into(),
        from: "a@x.co".into(),
        template_id: Some("welcome".into()),
        recurrence: Some(Some(BroadcastRecurrence::Interval {
            every_days: 7,
            time: "08:00".into(),
        })),
        data_source: Some(Some(BroadcastDataSourceInput::Url {
            url: "https://x.co/d.json".into(),
            header_name: Some(None),
            header_value: None,
        })),
        data: Some(None),
        ..Default::default()
    };
    nafru.broadcasts.create(&input).await.unwrap();
    assert_eq!(
        body(&mock.calls()[2]),
        json!({
            "segment_id": "s1", "from": "a@x.co", "template_id": "welcome",
            "recurrence": { "type": "interval", "every_days": 7, "time": "08:00" },
            "data_source": { "type": "url", "url": "https://x.co/d.json", "header_name": null },
            "data": null
        })
    );
}
