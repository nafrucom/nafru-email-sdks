# Nafru Email Rust SDK

The official **Nafru Email Rust SDK** (`nafru-email` crate). Nafru Email is a transactional and marketing **email API**
with a Resend-compatible surface. Use this async Rust SDK (`tokio` + `reqwest`, rustls) to send email from Rust
(transactional email, scheduled email, templates, batch sends), manage domains, contacts, segments and broadcasts, verify
webhooks, and let your own customers send from their Nafru Email account with "Connect with Nafru" (OAuth + PKCE).

[![crates.io](https://img.shields.io/crates/v/nafru-email.svg)](https://crates.io/crates/nafru-email)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/rust/LICENSE)

## Requirements

- Rust 1.85+ (edition 2024)
- A `tokio` runtime

## Installation

```sh
cargo add nafru-email
cargo add tokio --features macros,rt-multi-thread
```

## Quick start: send an email

```rust
use nafru_email::{NafruEmail, SendEmailInput, SendEmailOptions};

#[tokio::main]
async fn main() {
    let nafru = NafruEmail::new("nafru_123").unwrap(); // or NafruEmail::new("") to read NAFRU_API_KEY

    let result = nafru
        .emails
        .send(
            &SendEmailInput {
                from: Some("Acme <hello@example.com>".into()),
                to: vec!["ali@example.org".into()],
                subject: Some("Welcome".into()),
                html: Some("<p>Hello!</p>".into()),
                scheduled_at: Some("in 1 hour".into()), // optional: ISO 8601 or a relative expression, up to 30 days ahead
                ..Default::default()
            },
            SendEmailOptions::idempotency_key("signup-1042"), // retrying with the same key returns the same email
        )
        .await;

    match result {
        Ok(sent) => println!("{}", sent.id),
        Err(error) => eprintln!("{:?} {} {}", error.status_code, error.name, error.message),
    }
}
```

All other settings are optional and go through `NafruEmail::with_options`:

```rust
use nafru_email::{NafruEmail, NafruEmailOptions};
use std::time::Duration;

let nafru = NafruEmail::with_options(NafruEmailOptions {
    api_key: "nafru_123".into(),                    // empty: read from NAFRU_API_KEY
    base_url: "http://localhost:48787/api".into(),  // empty: DEFAULT_BASE_URL (https://email.nafru.com/api)
    max_retries: Some(3),                           // default 2
    timeout: Some(Duration::from_secs(10)),         // default 30 s
    ..Default::default()
})?;
```

Field names are `snake_case` just like the API (`reply_to`, `scheduled_at`, `first_name`), so they match the wire format
exactly. Optional fields that can be `null` are `Option<Option<T>>`: `None` is not sent, `Some(None)` sends `null` (e.g.
`first_name: Some(None)` clears the name). Fixed value sets (`TopicSubscription::OptIn`, `WebhookEventType::EmailDelivered`,
…) are enums; a new value from the server arrives as `Other(String)`.

## No sending in development

When `NODE_ENV=development`, `emails.send` and `emails.batch` (and `emails.send` on a connection client) **do not send**
email. Each email is written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the
same name, and the file paths and plain text are printed to the console. The response comes back with a `dev_…` id.
Change the folder with `dev_outbox: DevOutbox::Dir("tmp/mail".into())`, or turn it off with `DevOutbox::Off`.

## Errors

Every call returns `nafru_email::Result<T>`; the error type is `NafruError` (implements `std::error::Error`, works with `?`):

```rust
pub struct NafruError {
    pub status_code: Option<u16>,        // None on network errors/timeouts
    pub name: String,                    // validation_error, not_found, rate_limit_exceeded, timeout_error, application_error, …
    pub message: String,
    pub errors: Vec<NafruFieldError>,    // field details on 422
    pub retry_after: Option<u64>,        // seconds on 429
}
```

Misconfiguration (no API key and no `NAFRU_API_KEY`, a webhook secret without `whsec_`, an empty `state`) returns `invalid_argument` without
sending a request.

## Retries, idempotency and timeouts

- `429` is retried on every method, honoring `retry-after` (the request was rejected before being processed).
- `5xx`, network errors and timeouts are retried for `GET`/`DELETE` (300 ms × 2ⁿ, up to 8 s).
- `POST`/`PATCH` are **not** retried on server errors, because the email could be sent twice; they are retried if you
  pass an idempotency key.
- Defaults: 2 retries (`max_retries`), 30 s timeout (`timeout`). A custom transport (`transport`, the `Transport` trait)
  is available for tests and proxies.

## Resources

|                      |                                                                                                                |
| -------------------- | -------------------------------------------------------------------------------------------------------------- |
| `emails`             | `send` `batch` `get` `list` `update` `cancel`                                                                  |
| `domains`            | `create` `get` `list` `update` `remove` `verify`                                                               |
| `contacts`           | `create` `get` `list` `update` `remove`, `segments.{list,add,remove}`, `topics.{list,update}` (by id or email) |
| `contact_properties` | `create` `get` `list` `update` `remove`                                                                        |
| `segments`           | `create` `get` `list` `remove` `contacts`                                                                      |
| `topics`             | `create` `get` `list` `update` `remove`                                                                        |
| `broadcasts`         | `create` `get` `list` `update` `remove` `send` `cancel`                                                        |
| `templates`          | `create` `get` `list` `update` `remove` `publish` `duplicate` `put_translation` `remove_translation`           |
| `brand`              | `get` `update`: workspace brand (`update` replaces the **entire** brand; read it with `get` first)             |
| `webhooks`           | `create` `get` `list` `update` `remove`                                                                        |
| `api_keys`           | `create` `list` `remove`                                                                                       |
| `events`             | `send` `batch` `list`: custom events that trigger automations                                                  |

## Pagination

Lists are cursor-based (`limit`, `after`, `before`). To iterate over everything:

```rust
use nafru_email::{paginate, ListContactsQuery};

let mut contacts = paginate(|q| nafru.contacts.list(q), ListContactsQuery { limit: Some(100), ..Default::default() });
while let Some(contact) = contacts.next().await? {
    println!("{}", contact.email);
}
// or: let all = paginate(...).collect().await?;
```

If a page fails, `next` returns that error; the loop never stops silently.

## Recurring broadcasts

A broadcast can carry a recurrence rule (`recurrence`) and a data source (`data_source`) for `{{{data.*}}}` variables:

```rust
use nafru_email::*;

nafru.broadcasts.create(&CreateBroadcastInput {
    segment_id: "seg_1".into(),
    from: "Acme <hello@example.com>".into(),
    template_id: Some("weekly-digest".into()),
    recurrence: Some(Some(BroadcastRecurrence::Weekly { days: vec![1], time: "09:00".into() })),
    data_source: Some(Some(BroadcastDataSourceInput::Url {
        url: "https://example.com/digest.json".into(),
        header_name: None,
        header_value: None,
    })),
    ..Default::default()
}).await?;
// On update, Some(None) clears a field (sends null); None leaves it unchanged.
```

## Verifying webhook signatures

The server signs webhooks in the Svix / Standard Webhooks format. Use the **raw** body; JSON that has been parsed and
re-serialized will break the signature.

```rust
use nafru_email::{verify_webhook, VerifyWebhookInput};

let ok = verify_webhook(&VerifyWebhookInput {
    payload: &raw_body,
    id: svix_id,               // "svix-id" header
    timestamp: svix_timestamp, // "svix-timestamp" header
    signature: svix_signature, // "svix-signature" header
    secret: &std::env::var("NAFRU_WEBHOOK_SECRET").unwrap(), // signing_secret from the webhooks.create response
    ..Default::default()
})?; // malformed secret: Err; bad signature/timestamp: Ok(false)
if !ok {
    // respond with 400
}
```

A timestamp more than 5 minutes in the past or future is rejected (`tolerance_seconds`). During key rotation, when several
signatures arrive, one valid signature is enough. The comparison is constant-time.

## Connect with Nafru (for apps)

If you want your product's customers to send from **their own** Nafru Email account, don't ask them to copy an API key:
register your app in Nafru Email (Developer → Apps) and use `NafruConnect`.

```rust
use nafru_email::*;

let connect = NafruConnect::new(NafruConnectOptions {
    client_id: std::env::var("NAFRU_CLIENT_ID").unwrap(),
    client_secret: std::env::var("NAFRU_CLIENT_SECRET").unwrap(), // server-side only
    // base_url: optional, defaults to DEFAULT_BASE_URL; locally "http://localhost:48787/api".into()
    // web_url: the consent screen; if omitted, the trailing /api is stripped from base_url (https://email.nafru.com)
    ..Default::default()
})?;

// 1) Redirect the customer. Store code_verifier and state in the session.
let AuthorizeUrl { url, code_verifier } = connect.authorize_url(&AuthorizeUrlInput {
    redirect_uri: "https://myapp.example/nafru/callback".into(),
    state,
    scopes: vec![AppScope::EmailsSend, AppScope::TemplatesRead, AppScope::SendersRead, AppScope::ConnectionRead],
    login_hint: None,
})?;

// 2) On return, verify the state and exchange the code for a connection.
let grant = connect.exchange(&ExchangeInput { code, code_verifier, redirect_uri }).await?;
// Map grant.connection_id to the customer; store grant.refresh_token ENCRYPTED.

// 3) Call on the customer's behalf. The access token is refreshed automatically; the refresh token CHANGES on every refresh.
let db = db.clone();
let connection = connect.connection(&connection_id, ConnectionOptions::new(load(&connection_id).await, move |tokens| {
    let db = db.clone();
    async move { db.save_refresh_token(tokens.refresh_token).await } // the old token is invalid until this is persisted
}));

let status = connection.status().await?; // ready, missing: ["domain", "sender", …], setup_url
connection.senders.list().await?;
connection.templates.list().await?; // the customer's templates + your app's bundle
connection.emails.send(&SendEmailInput {
    to: vec![to],
    template: Some(EmailTemplate { id: "welcome".into(), variables: None }),
    ..Default::default()
}, Default::default()).await?;
```

- If the customer disconnected or the refresh token is invalid, you get `error.name == "connection_revoked"`; ask the
  customer to reconnect.
- Concurrent calls on the same connection (and its `clone`s) share a single refresh (single flight). If several processes
  use the same connection, keep the refresh token in a shared, consistent store and serialize refreshes with a lock:
  reusing an old refresh token revokes the connection for security. Don't call `connect.connection(...)` on every request;
  build it once and share it.
- If `on_token_refresh` returns an error, the call fails with `token_persist_failed`; the new token stays in memory and
  saving it is retried on the next call.
- Management endpoints (API keys, domains, contacts, broadcasts) can't be called with a connection token; only sending,
  reading and discovery are available.
- When the customer closes their account, call `connect.revoke(&refresh_token).await?`.

## Deprecation warnings

When the API deprecates this SDK version (`Deprecation` response header), a warning is printed to stderr once per client
instance (including the `Sunset` date and `Link` URL when present). The call does not fail. Deprecated versions are
listed in [deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Don't embed your API key or client secret in client applications (WASM, distributed desktop
  apps). Even a `sending_access` key can send email.
- **HTTPS enforced.** `base_url` and `web_url` must use `https`; plain `http` is accepted only for `localhost`,
  `*.localhost`, `127.0.0.0/8` and `[::1]` (local development). Otherwise construction fails with `invalid_argument`.
  TLS certificate verification is always on and cannot be disabled.
- **Redirects refused.** The API never redirects, so the default transport doesn't follow redirects (following one could
  leak `Authorization` to another host); a 3xx becomes an `unexpected_redirect` error and is never retried. If you pass
  your own `reqwest::Client` via `ReqwestTransport::new`, build it with `redirect::Policy::none()`.
- **Input checks.** Empty, `.` or `..` ids and idempotency keys with control characters (CR, LF, …) are rejected before
  any request. Response bodies are capped at 10 MB (`response_too_large`).
- **Secrets redacted.** `Debug` output of the clients, options, `ConnectionGrant`, `ConnectionTokens`, `CreatedApiKey`,
  webhook secrets and `HttpRequest` (the `authorization` header) shows `[REDACTED]`; errors never contain keys or tokens.
- **Webhooks.** Verify against the raw request body exactly as received; comparison is constant-time and stale or future
  timestamps (beyond 5 minutes) are rejected.
- **Reporting vulnerabilities:** don't open a public issue. Use GitHub
  [private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email
  security@nafru.com; see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

```sh
cargo test                          # unit + integration tests (no network, fake transport)
cargo clippy --all-targets -- -D warnings
cargo package                       # validates the release package
```

## Troubleshooting

Every error is a `NafruError`; match on `error.name`.

| `error.name` / symptom                                                      | What it means and what to do                                                                                                                                                                                                                                                                   |
| --------------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `unauthorized`, `invalid_api_key`                                           | The API key is wrong or revoked, or you called `NafruEmail::new("")` without `NAFRU_API_KEY` set in the process environment. Check the key in the dashboard.                                                                                                                                   |
| `forbidden`                                                                 | The key lacks permission, e.g. a `sending_access` key can send but can't list or manage resources. Use a `full_access` key for management calls.                                                                                                                                               |
| `validation_error`                                                          | The request body was rejected (422). Read `error.errors` (`field`, `message`) for per-field details.                                                                                                                                                                                           |
| `rate_limit_exceeded`                                                       | 429. Already retried automatically (`max_retries`, default 2) honoring `retry-after`; if it still fails, `error.retry_after` says how many seconds to wait.                                                                                                                                    |
| `timeout_error`, `application_error` (`status_code: None`)                  | Network failure or timeout (`timeout`, default 30 s). `GET`/`DELETE` are retried; `POST`/`PATCH` are retried only with an idempotency key, so pass `SendEmailOptions::idempotency_key(...)` to make retries safe.                                                                              |
| `unexpected_redirect`                                                       | The server answered with a 3xx. The API never redirects: check `base_url` (include `/api`, use `https`) and any proxy in between.                                                                                                                                                              |
| `invalid_argument`: "baseUrl https kullanmalı (http yalnız localhost için)" | `base_url`/`web_url` must be `https`; `http` only works for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`. Other `invalid_argument` errors: missing API key, empty/`.`/`..` id, idempotency key with control characters, empty `state` or `scopes`, a webhook secret without `whsec_`. |
| `response_too_large`                                                        | The response body exceeded 10 MB, usually a misbehaving proxy or wrong `base_url`.                                                                                                                                                                                                             |
| `connection_revoked` (Connect)                                              | The customer disconnected or the refresh token is invalid/reused. Ask the customer to connect again.                                                                                                                                                                                           |
| `token_persist_failed` (Connect)                                            | Your `on_token_refresh` callback returned an error. The new refresh token is kept in memory and saving is retried on the next call; fix the storage, or the connection breaks when the process restarts.                                                                                       |
| `verify_webhook` returns `Ok(false)`                                        | Pass the **raw** body (not re-serialized JSON), the endpoint's own `whsec_…` secret, and the `svix-id`, `svix-timestamp`, `svix-signature` headers unchanged. Timestamps more than 5 minutes off are rejected, so check the server clock.                                                      |
| Emails are not being sent, ids start with `dev_`                            | `NODE_ENV=development` turns on the dev outbox: emails are written to `.nafru/emails/` instead. Set `dev_outbox: DevOutbox::Off` (or unset `NODE_ENV`) to send for real.                                                                                                                       |

## Links

- API documentation and dashboard: https://email.nafru.com
- Source for all SDKs: https://github.com/nafrucom/nafru-email-sdks

| Language             | Package                                                                                                 |
| -------------------- | ------------------------------------------------------------------------------------------------------- |
| TypeScript / Node.js | [`@nafrucom/email`](https://www.npmjs.com/package/@nafrucom/email)                                      |
| Python               | [`nafru-email`](https://pypi.org/project/nafru-email/)                                                  |
| PHP                  | [`nafrucom/email`](https://packagist.org/packages/nafrucom/email)                                       |
| Ruby                 | [`nafru-email`](https://rubygems.org/gems/nafru-email)                                                  |
| Java                 | [`com.nafru:nafru-email`](https://central.sonatype.com/artifact/com.nafru/nafru-email)                  |
| Go                   | [`github.com/nafrucom/nafru-email-sdks/go`](https://pkg.go.dev/github.com/nafrucom/nafru-email-sdks/go) |
| .NET                 | [`Nafru.Email`](https://www.nuget.org/packages/Nafru.Email)                                             |
| Rust                 | [`nafru-email`](https://crates.io/crates/nafru-email)                                                   |
| Swift                | [`nafru-email-sdks`](https://github.com/nafrucom/nafru-email-sdks) (SwiftPM)                            |

## Support

- Questions and how-to: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never a public issue)

See [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md) for details and [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md) to contribute.

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/rust/LICENSE).
