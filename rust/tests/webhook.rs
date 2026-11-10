use nafru_email::{VerifyWebhookInput, verify_webhook};
use serde_json::Value;

fn vector() -> Value {
    let text = std::fs::read_to_string(concat!(
        env!("CARGO_MANIFEST_DIR"),
        "/../webhook-test-vector.json"
    ))
    .expect("sdks/webhook-test-vector.json");
    serde_json::from_str(&text).unwrap()
}

fn input<'a>(v: &'a Value, payload: &'a str) -> VerifyWebhookInput<'a> {
    VerifyWebhookInput {
        payload,
        id: v["id"].as_str().unwrap(),
        timestamp: v["timestamp"].as_str().unwrap(),
        signature: v["signature"].as_str().unwrap(),
        secret: v["secret"].as_str().unwrap(),
        tolerance_seconds: None,
        now_seconds: v["now_seconds"].as_i64(),
    }
}

#[test]
fn shared_vector_verifies_and_tampering_fails() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    assert!(verify_webhook(&input(&v, payload)).unwrap());
    assert!(!verify_webhook(&input(&v, &payload.replace("em_123", "em_124"))).unwrap());
}

#[test]
fn rotated_signatures_any_match_is_enough() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    let signature = format!("v1,AAAA v2,x {}", v["signature"].as_str().unwrap());
    assert!(
        verify_webhook(&VerifyWebhookInput {
            signature: &signature,
            ..input(&v, payload)
        })
        .unwrap()
    );
}

#[test]
fn stale_or_bad_timestamp_is_false() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    let now = v["now_seconds"].as_i64().unwrap();
    assert!(
        !verify_webhook(&VerifyWebhookInput {
            now_seconds: Some(now + 301),
            ..input(&v, payload)
        })
        .unwrap()
    );
    assert!(
        verify_webhook(&VerifyWebhookInput {
            now_seconds: Some(now - 300),
            ..input(&v, payload)
        })
        .unwrap()
    );
    assert!(
        !verify_webhook(&VerifyWebhookInput {
            timestamp: "abc",
            ..input(&v, payload)
        })
        .unwrap()
    );
}

#[test]
fn bad_secret_is_an_error() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    assert!(
        verify_webhook(&VerifyWebhookInput {
            secret: "abc",
            ..input(&v, payload)
        })
        .is_err()
    );
    assert!(
        verify_webhook(&VerifyWebhookInput {
            secret: "whsec_%%%",
            ..input(&v, payload)
        })
        .is_err()
    );
}

#[test]
fn empty_headers_are_false_not_panic() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    for (id, timestamp, signature) in [
        (
            "",
            v["timestamp"].as_str().unwrap(),
            v["signature"].as_str().unwrap(),
        ),
        (
            v["id"].as_str().unwrap(),
            "",
            v["signature"].as_str().unwrap(),
        ),
        (
            v["id"].as_str().unwrap(),
            v["timestamp"].as_str().unwrap(),
            "",
        ),
    ] {
        assert!(
            !verify_webhook(&VerifyWebhookInput {
                id,
                timestamp,
                signature,
                ..input(&v, payload)
            })
            .unwrap()
        );
    }
}

#[test]
fn future_timestamp_outside_tolerance_is_false() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    let now = v["now_seconds"].as_i64().unwrap();
    assert!(
        !verify_webhook(&VerifyWebhookInput {
            now_seconds: Some(now - 301),
            ..input(&v, payload)
        })
        .unwrap()
    );
}

#[test]
fn signatures_after_the_32nd_are_ignored() {
    let v = vector();
    let payload = v["payload"].as_str().unwrap();
    let valid = v["signature"].as_str().unwrap();
    let padding = vec!["v1,AAAA"; 32].join(" ");
    let late = format!("{padding} {valid}");
    assert!(
        !verify_webhook(&VerifyWebhookInput {
            signature: &late,
            ..input(&v, payload)
        })
        .unwrap()
    );
    let in_bound = format!("{} {valid}", vec!["v1,AAAA"; 31].join(" "));
    assert!(
        verify_webhook(&VerifyWebhookInput {
            signature: &in_bound,
            ..input(&v, payload)
        })
        .unwrap()
    );
}
