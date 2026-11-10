# Nafru Email Swift SDK

The official **Nafru Email Swift SDK** (`NafruEmail`). Nafru Email is a transactional and marketing **email API** with a
Resend-compatible surface. Use this Swift SDK to send email from Swift (transactional email, scheduled email, templates,
batch sends), manage domains, contacts, segments and broadcasts, verify webhooks, and let your own customers send from
their Nafru Email account with "Connect with Nafru" (OAuth). It has no dependencies: it uses `URLSession` (async/await),
`Codable` and `CryptoKit`.

[![SwiftPM compatible](https://img.shields.io/badge/SwiftPM-compatible-brightgreen.svg)](https://swift.org/package-manager/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/swift/LICENSE)

## Requirements

- Swift 5.9+
- macOS 12+, iOS 15+, tvOS 15+, watchOS 8+
- Linux is not supported yet (`CryptoKit` and `URLSession.data(for:)` are only available on Apple platforms).

## Installation

In `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/nafrucom/nafru-email-sdks", from: "0.1.1")
],
targets: [
    .target(name: "MyApp", dependencies: [.product(name: "NafruEmail", package: "nafru-email-sdks")])
]
```

Xcode: File → Add Package Dependencies… → `https://github.com/nafrucom/nafru-email-sdks`.

## Quick start: send an email

```swift
import NafruEmail

let nafru = try NafruEmail("nafru_...")
// No key? `try NafruEmail()` reads the NAFRU_API_KEY environment variable.
// baseURL is optional: defaults to NafruSDK.defaultBaseURL (https://email.nafru.com/api).
// Locally: try NafruEmail(key, baseURL: "http://localhost:48787/api")

let sent = try await nafru.emails.send(
    SendEmailInput(
        from: "Acme <hello@example.com>",
        to: ["ali@example.org"],
        subject: "Welcome",
        scheduledAt: "in 1 hour", // optional: ISO 8601 or a relative expression, up to 30 days ahead
        html: "<p>Hello!</p>"
    ),
    idempotencyKey: "signup-1042" // retrying with the same key returns the same email
)
print(sent.id)
```

Swift properties are camelCase (`replyTo`, `scheduledAt`, `firstName`) and are sent as `snake_case` on the wire, just like
the API (`reply_to`, `scheduled_at`). For `String??` fields, `nil` leaves the field out and `.some(nil)` explicitly sends
`null` (clearing the value):

```swift
try await nafru.contacts.update("ali@example.org", UpdateContactInput(firstName: .some(nil), properties: ["plan": "pro", "seats": 3]))
```

Don't embed your API key in an app bundle (iOS/macOS client); even a `sending_access` key can send email. Use the SDK on
the server (Vapor, Hummingbird) or in your own backend.

## No sending in development

When the `NODE_ENV=development` environment variable is set, `emails.send` and `emails.batch` (and `emails.send` on a
connection client) **do not send** email. Each email is written under `.nafru/emails/` as plain text (`.txt`, headers +
body) plus an `.html` file with the same name, and the file paths and plain text are printed to the console. The response
comes back with a `dev_…` id. Change the folder with `devOutbox: .directory("tmp/mail")`, or turn it off with
`devOutbox: .disabled`.

## Errors

Every failed call throws `NafruError`:

```swift
do {
    _ = try await nafru.emails.get("em_123")
} catch let error as NafruError {
    error.statusCode // Int? — nil on network errors/timeouts
    error.name       // validation_error, not_found, rate_limit_exceeded, application_error, timeout_error, …
    error.message
    error.errors     // [NafruFieldError]? — field details on 422
    error.retryAfter // Double? — seconds on 429
}
```

## Retries, idempotency and timeouts

- `429` is retried on every method, honoring `retry-after` (the request was rejected before being processed).
- `5xx` and network errors are retried for `GET`/`DELETE`.
- `POST`/`PATCH` are **not** retried on server errors, because the email could be sent twice; they are retried if you
  pass an `idempotencyKey`.
- Defaults: 2 retries (`maxRetries`), 30 s timeout (`timeout`). Backoff is 300 ms × 2ⁿ, up to 8 s.
- For tests or a proxy, pass your own `NafruTransport` implementation via `transport:`.

## Resources

|                     |                                                                                                                |
| ------------------- | -------------------------------------------------------------------------------------------------------------- |
| `emails`            | `send` `batch` `get` `list` `update` `cancel`                                                                  |
| `domains`           | `create` `get` `list` `update` `remove` `verify`                                                               |
| `contacts`          | `create` `get` `list` `update` `remove`, `segments.{list,add,remove}`, `topics.{list,update}` (by id or email) |
| `contactProperties` | `create` `get` `list` `update` `remove`                                                                        |
| `segments`          | `create` `get` `list` `remove` `contacts`                                                                      |
| `topics`            | `create` `get` `list` `update` `remove`                                                                        |
| `broadcasts`        | `create` `get` `list` `update` `remove` `send` `cancel`                                                        |
| `templates`         | `create` `get` `list` `update` `remove` `publish` `duplicate` `putTranslation` `removeTranslation`             |
| `brand`             | `get` `update`: workspace brand (`update` replaces the ENTIRE brand; read it with `get` first)                 |
| `webhooks`          | `create` `get` `list` `update` `remove`                                                                        |
| `apiKeys`           | `create` `list` `remove`                                                                                       |
| `events`            | `send` `batch` `list`: custom events that trigger automations                                                  |

## Pagination

Lists are cursor-based (`limit`, `after`, `before`). To iterate over everything:

```swift
for try await contact in paginate(nafru.contacts.list, ListContactsQuery(limit: 100)) {
    print(contact.email)
}
```

If a page fails, the loop throws that error.

## Recurring broadcasts and data sources

```swift
try await nafru.broadcasts.create(CreateBroadcastInput(
    segmentId: "seg_123",
    from: "Acme <newsletter@acme.example>",
    subject: "Weekly digest",
    html: "<p>{{{data.title}}}</p>",
    dataSource: .url("https://acme.example/feed.json", headerName: "X-Key", headerValue: "secret"), // fetched with GET at send time
    recurrence: .weekly(days: [1], time: "09:00") // Mondays at 09:00 (workspace time zone)
))
```

`recurrence`: `.weekly(days:time:)`, `.monthly(day:time:)`, `.interval(everyDays:time:)`. On update, `.some(nil)` removes
the rule. The `dataSource` in responses is `.manual`, `.url(…, headerName:, hasHeaderValue:)` or
`.webhook(triggerUrl:secret:)`; types this version doesn't know decode as `.unknown(type:)`.

## Sending with templates, and custom events

```swift
try await nafru.emails.send(SendEmailInput(
    from: "Acme <hello@acme.example>",
    to: ["ali@example.org"],
    template: EmailTemplate(id: "welcome", variables: ["NAME": "Ali"])
))

try await nafru.events.send(SendEventInput(
    name: "plan_upgraded",
    contact: .email("ali@example.org"), // created if the contact doesn't exist
    properties: ["plan": "pro", "seats": 3]
))
```

## Verifying webhook signatures

The server signs webhooks in the Svix / Standard Webhooks format. Use the **raw** body; JSON that has been parsed and
re-serialized will break the signature.

```swift
let ok = try verifyWebhook(
    payload: rawBody, // String, the request body exactly as received
    headers: WebhookHeaders(id: svixId, timestamp: svixTimestamp, signature: svixSignature),
    secret: webhookSecret // signingSecret from the webhooks.create response (whsec_…)
)
guard ok else { /* respond with 400 */ }
let event = try JSONDecoder().decode(WebhookPayload<JSONValue>.self, from: Data(rawBody.utf8))
```

Returns `false` if the timestamp is more than 5 minutes in the past or future (`toleranceSeconds`). During key rotation,
when several signatures arrive, one valid signature is enough. A malformed `secret` throws (configuration error).

## Connect with Nafru (for apps)

If you want your product's customers to send from **their own** Nafru Email account, don't ask them to copy an API key:
register your app in Nafru Email (Developer → Apps) and use `NafruConnect`. The `clientSecret` stays on your server only.

```swift
let connect = try NafruConnect(
    clientId: env["NAFRU_CLIENT_ID"]!,
    clientSecret: env["NAFRU_CLIENT_SECRET"]!
    // baseURL: optional (defaults to https://email.nafru.com/api; locally http://localhost:48787/api)
    // webURL: the consent screen; if omitted, the trailing /api is stripped from baseURL
)

// 1) Redirect the customer. Store codeVerifier and state in the session.
let authorize = try connect.authorizeUrl(
    redirectUri: "https://myapp.example/nafru/callback",
    state: state,
    scopes: [.emailsSend, .templatesRead, .sendersRead, .connectionRead]
)

// 2) On return, verify the state and exchange the code for a connection.
let grant = try await connect.exchange(code: code, codeVerifier: authorize.codeVerifier, redirectUri: redirectUri)
// Map grant.connectionId to the customer; store grant.refreshToken ENCRYPTED.

// 3) Call on the customer's behalf. The access token is refreshed automatically; the refresh token CHANGES on every refresh.
let connection = connect.connection(grant.connectionId, ConnectionOptions(refreshToken: try await load(grant.connectionId)) { tokens in
    try await save(grant.connectionId, tokens.refreshToken) // the old token is invalid until this is persisted
})

let status = try await connection.status() // ready, missing: ["domain", "sender", …], setupUrl
_ = try await connection.senders.list()
_ = try await connection.templates.list() // the customer's templates + your app's bundle
_ = try await connection.emails.send(SendEmailInput(to: ["ali@example.org"], template: EmailTemplate(id: "welcome")))
```

- If the customer disconnected or the refresh token is invalid, you get `error.name == "connection_revoked"`; ask the
  customer to reconnect.
- Concurrent calls on the same connection share a single refresh (single flight, via an `actor`). If several processes
  use the same connection, keep the refresh token in a shared, consistent store and serialize refreshes with a lock:
  reusing an old refresh token revokes the connection.
- If `onTokenRefresh` throws, the call fails with `token_persist_failed`; the new token stays in memory and saving it is
  retried on the next call.
- A `401 invalid_token` caused by an expired token is refreshed once and retried.
- Management endpoints (API keys, domains, contacts, broadcasts) can't be called with a connection token; only sending,
  reading and discovery are available.
- When the customer closes their account, call `try await connect.revoke(refreshToken: …)`.

## Deprecation warnings

If the SDK version you use has been deprecated, the API returns a `Deprecation` header and the SDK prints a warning to
stderr once per client. The call still succeeds. Deprecated versions and their sunset dates are listed in
[deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Never ship an API key or `clientSecret` inside an iOS/macOS app bundle; even a `sending_access`
  key can send email. Use the SDK from your backend.
- **HTTPS enforced.** `baseURL` and `webURL` must use `https`; plain `http` is accepted only for `localhost`, `*.localhost`,
  `127.0.0.0/8` and `[::1]` (local development). Anything else throws `invalid_argument` at construction time.
- **Redirects refused.** The API never redirects, so the default transport does not follow redirects (a redirect could leak
  the `Authorization` header to another host). A 3xx response throws `unexpected_redirect` and is never retried.
- **Input checks.** Empty, `.` and `..` path parameters and `idempotencyKey` values with control characters (CR/LF) are
  rejected with `invalid_argument` before any request. Response bodies over 10 MB throw `response_too_large`.
- **Secrets redacted.** `print`, string interpolation, `debugPrint` and `dump` of `NafruEmail`, `NafruConnect`,
  `ConnectionGrant`, `ConnectionOptions`, `CreatedApiKey` and webhook secrets show only a prefix like `nfr_****`. Errors never
  contain keys or tokens.
- **Webhooks.** Verify against the **raw** request body (`String` or `Data`), never re-serialized JSON. Signatures are
  compared in constant time, the timestamp tolerance applies in both directions, and missing headers return `false`.
- **TLS** certificate verification is never disabled. PKCE verifiers use the system CSPRNG.
- **Reporting vulnerabilities:** please don't open a public issue. Use
  [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email
  security@nafru.com. See [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

```sh
cd sdks && swift test
```

The version lives in one place: `swift/Sources/NafruEmail/Version.swift` (`NafruSDK.version`). Releases are made with a
git tag (`vX.Y.Z`).

## Troubleshooting

Every failure is a thrown `NafruError`; check `error.name` (and `error.statusCode`, `error.message`, `error.errors`).

- **`unauthorized` (401) / `invalid_api_key` (403):** the key is wrong, revoked or missing. `NafruEmail()` without an
  argument reads `NAFRU_API_KEY`; if that is unset or empty the initializer throws "Nafru SDK: apiKey gerekli".
- **`forbidden` (403):** the key lacks permission, e.g. a `sending_access` key can send but cannot list or manage
  resources. Create a `full_access` key for management calls.
- **`validation_error` (422):** the request body is invalid. `error.errors` lists each `field` and `message`.
- **`rate_limit_exceeded` (429):** already retried automatically (`maxRetries`, honoring `Retry-After`, capped at 8 s).
  If it still fails, `error.retryAfter` says how many seconds to wait.
- **`timeout_error` / `application_error` with `statusCode == nil`:** a network failure or timeout. `GET`/`DELETE` are
  retried; `POST`/`PATCH` are retried only when you pass `idempotencyKey`, so the email is never sent twice.
- **`unexpected_redirect` (3xx):** the base URL points at something that redirects (wrong host, missing `/api`, a proxy,
  http→https upgrade). Redirects are never followed; fix `baseURL`.
- **"baseUrl https kullanmalı (http yalnız localhost için)" (`invalid_argument`):** `baseURL`/`webURL` must be `https`;
  `http` works only for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **`invalid_argument` on a call:** an empty, `.` or `..` id/email/alias/locale, or an `idempotencyKey` that is empty or
  contains control characters. No request was sent.
- **`response_too_large`:** the response exceeded 10 MB, usually a misbehaving proxy or the wrong `baseURL`.
- **`connection_revoked` (Connect):** the customer disconnected your app or the refresh token is invalid or was reused.
  Ask the customer to connect again.
- **`token_persist_failed` (Connect):** your `onTokenRefresh` threw. The new refresh token is kept in memory and saving
  is retried on the next call; fix your storage, otherwise the connection breaks after a restart.
- **`verifyWebhook` returns `false`:** pass the **raw** body exactly as received (not re-encoded JSON), the endpoint's
  own `whsec_` secret, and the `svix-id`, `svix-timestamp`, `svix-signature` headers unchanged. Also check the server
  clock: timestamps more than 5 minutes off (either direction) are rejected. A malformed secret throws instead.
- **Emails are not being sent, ids start with `dev_`:** `NODE_ENV=development` is set, so the dev outbox writes emails to
  `.nafru/emails/` instead of sending. Pass `devOutbox: .disabled` or unset `NODE_ENV`.

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
- Bugs in the SDK: [GitHub Issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never a public issue)
- Contributing: [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md)

More in [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/swift/LICENSE).
