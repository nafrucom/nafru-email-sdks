# Nafru Email Ruby SDK

The official **Nafru Email Ruby SDK** lets you send email from Ruby (and Rails) through the Nafru Email API. Use it for
transactional email (sign-up confirmations, password resets, receipts) and marketing broadcasts, to manage contacts, templates and
domains, to trigger automations with custom events, and to verify webhooks. The email API is Resend-compatible, so request and
response shapes will feel familiar if you are coming from Resend.

[![Gem Version](https://img.shields.io/gem/v/nafru-email)](https://rubygems.org/gems/nafru-email)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/ruby/LICENSE)

## Requirements

- Ruby 3.1 or later
- No dependencies: only the standard library (`net/http`, `json`, `openssl`).

## Installation

```sh
gem install nafru-email
# or in your Gemfile: gem "nafru-email"
```

## Quick start: send an email

```ruby
require "nafru_email"

nafru = NafruEmail.new("nafru_123")
# NafruEmail.new with no key reads the NAFRU_API_KEY environment variable.
# Optional settings: NafruEmail.new("nafru_123", base_url: "http://localhost:48787/api", max_retries: 2, timeout: 30)
# base_url defaults to Nafru::Email::DEFAULT_BASE_URL (https://email.nafru.com/api).

email = nafru.emails.send(
  {
    from: "Acme <hello@example.com>",
    to: "ali@example.org",
    subject: "Welcome",
    html: "<p>Hello!</p>",
    scheduled_at: "in 1 hour" # optional: ISO 8601 or a relative expression, up to 30 days ahead
  },
  idempotency_key: "signup-1042" # retrying with the same key returns the same email
)
email[:id]
```

Body fields are `snake_case`, exactly as in the API (`reply_to`, `scheduled_at`, `first_name`); there is no conversion layer. Input
hashes may use symbol or string keys; responses are hashes with **symbol keys**. The full shapes live in `sig/nafru_email.rbs` (checkable
with Steep/RBS).

> `emails.send` and `events.send` shadow Ruby's `Object#send`; use `__send__` / `public_send` if you need dynamic dispatch.

## No real sending in development (dev outbox)

When `NODE_ENV=development`, `emails.send` and `emails.batch` (and `emails.send` on a connection client) do **not** send anything.
Each email is written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the same name, and the
file paths and plain text are printed to the console. The response is `{ id: "dev_…" }`. Change the folder with
`dev_outbox: "tmp/mail"`, or turn it off with `dev_outbox: false`.

## Errors

Every failed call raises `Nafru::Email::Error`:

```ruby
begin
  nafru.emails.send({ to: "ali@example.org", text: "hi" })
rescue Nafru::Email::Error => e
  e.status_code  # Integer; nil on network errors and timeouts
  e.name         # validation_error, not_found, rate_limit_exceeded, application_error, timeout_error, …
  e.message
  e.errors       # on 422: [{ field:, message: }]
  e.retry_after  # on 429: seconds to wait
end
```

Configuration problems such as a missing API key (none passed and `NAFRU_API_KEY` unset) raise `ArgumentError`.

## Retries, timeouts and idempotency

- `429` is retried for every method, honoring `retry-after` (the request was rejected before it was processed).
- `5xx` responses and network errors are retried for `GET`/`DELETE` (300 ms × 2ⁿ, at most 8 s).
- `POST`/`PATCH` are **not** retried on server errors, because the email could go out twice. Pass an `idempotency_key` and they are.
- Defaults: 2 retries (`max_retries:`) and a 30 s timeout (`timeout:`, in seconds).
- Custom transport (`transport:`): any object that responds to `call(method:, url:, headers:, body:, timeout:)` and returns a
  `Nafru::Email::Response` (tests, proxies, persistent connection pools). The default `Net::HTTP` transport opens a new connection
  per request.

## Resources

| Resource             | Methods                                                                                                        |
| -------------------- | -------------------------------------------------------------------------------------------------------------- |
| `emails`             | `send` `batch` `get` `list` `update` `cancel`                                                                  |
| `domains`            | `create` `get` `list` `update` `remove` `verify`                                                               |
| `contacts`           | `create` `get` `list` `update` `remove`, `segments.{list,add,remove}`, `topics.{list,update}` (by id or email) |
| `contact_properties` | `create` `get` `list` `update` `remove`                                                                        |
| `segments`           | `create` `get` `list` `remove` `contacts`                                                                      |
| `topics`             | `create` `get` `list` `update` `remove`                                                                        |
| `broadcasts`         | `create` `get` `list` `update` `remove` `send` `cancel`                                                        |
| `templates`          | `create` `get` `list` `update` `remove` `publish` `duplicate` `put_translation` `remove_translation`           |
| `brand`              | `get` `update`: workspace brand (`update` replaces the whole brand; read it with `get` first)                  |
| `webhooks`           | `create` `get` `list` `update` `remove`                                                                        |
| `api_keys`           | `create` `list` `remove`                                                                                       |
| `events`             | `send` `batch` `list`: custom events that trigger automations                                                  |

## Pagination

Lists are cursor-based (`limit`, `after`, `before`). To walk every page (the enumerator raises if a page fails):

```ruby
Nafru::Email.paginate(nafru.contacts.method(:list), limit: 100).each do |contact|
  puts contact[:email]
end
```

## Templates

```ruby
nafru.templates.create({ name: "Welcome", alias: "welcome", subject: "Welcome {{{NAME|friend}}}",
                         html: "<p>Hello {{{NAME|friend}}}</p>", brand: { mode: "inherit" } })
nafru.templates.publish("welcome")
nafru.emails.send({ from: "Acme <hello@acme.example>", to: "ali@example.org",
                    template: { id: "welcome", variables: { NAME: "Ali" } } })
```

## Recurring broadcasts and data sources

A broadcast with `recurrence` repeats on a schedule, and `data` / `data_source` fill the template's `{{{data.*}}}` variables:

```ruby
nafru.broadcasts.create({
  segment_id: "seg_…", from: "Acme <hello@acme.example>", subject: "Weekly digest",
  html: "<p>Plan: {{{data.plan}}}</p>",
  recurrence: { type: "weekly", days: [1], time: "09:00" }, # monthly { day:, time: } · interval { every_days:, time: }
  data_source: { type: "url", url: "https://acme.example/digest.json", header_name: "x-key", header_value: "…" }
})
nafru.broadcasts.update("bc_…", { recurrence: nil }) # nil clears a field; omitted fields are left unchanged
nafru.broadcasts.send("bc_…", { data: { plan: "pro" } })
```

Because responses are hashes, an unknown `type` (a new recurrence kind, for example) does not break parsing; it is returned as is.

## Custom events

```ruby
nafru.events.send({ name: "plan_upgraded", contact: { email: "ali@example.org" }, properties: { plan: "pro", seats: 3 } })
```

## Verifying webhook signatures

Webhooks are signed in the Svix / Standard Webhooks format. Use the **raw** request body; JSON that has been parsed and re-encoded
will not match the signature.

```ruby
# Rails: request.raw_post; Rack: request.body.read
ok = Nafru::Email::Webhook.verify(
  payload: request.raw_post,
  headers: {
    id: request.headers["svix-id"],
    timestamp: request.headers["svix-timestamp"],
    signature: request.headers["svix-signature"]
  },
  secret: ENV.fetch("NAFRU_WEBHOOK_SECRET") # the signing_secret from the webhooks.create response
)
head :bad_request unless ok
```

Timestamps more than 5 minutes in the past or future are rejected (`tolerance_seconds:`). During key rotation several signatures may
be sent; one valid signature is enough. A malformed `secret` (no `whsec_` prefix, not base64) raises `ArgumentError`.

## Connect with Nafru (for apps)

If you want your customers to send from **their own** Nafru Email account, don't ask them to paste an API key. Register your app in
Nafru Email (Developer → Apps) and use `NafruConnect`, which implements an OAuth flow with PKCE.

```ruby
connect = NafruConnect.new(
  client_id: ENV.fetch("NAFRU_CLIENT_ID"),
  client_secret: ENV.fetch("NAFRU_CLIENT_SECRET") # server side only
  # base_url: optional (defaults to https://email.nafru.com/api; use "http://localhost:48787/api" locally)
  # web_url: the consent screen; defaults to base_url with the trailing /api removed
)

# 1) Redirect the customer. Store code_verifier and state in the session.
auth = connect.authorize_url(
  redirect_uri: "https://myapp.example/nafru/callback",
  state: session[:nafru_state] = SecureRandom.hex(16),
  scopes: %w[emails.send templates.read senders.read connection.read]
)
session[:nafru_verifier] = auth[:code_verifier]
redirect_to auth[:url], allow_other_host: true

# 2) On the callback, check state and exchange the code for a connection.
grant = connect.exchange(code: params[:code], code_verifier: session[:nafru_verifier], redirect_uri: redirect_uri)
# Map grant[:connection_id] to the customer; store grant[:refresh_token] ENCRYPTED.

# 3) Call the API on the customer's behalf. The access token refreshes automatically; the refresh token CHANGES on every refresh.
connection = connect.connection(connection_id, refresh_token: load(connection_id)) do |tokens|
  save(connection_id, tokens[:refresh_token]) # the old token is invalid until this is persisted
end

connection.status          # ready, missing: ["domain", "sender", …], setup_url
connection.senders.list
connection.templates.list  # the customer's templates + your app's bundle
connection.emails.send({ from: from, to: to, template: { id: "welcome", variables: {} } })
```

- If the customer disconnected your app or the refresh token is invalid, `Error#name == "connection_revoked"`; ask the customer to
  connect again.
- Concurrent threads sharing one connection object share a single refresh (single flight, `Mutex`). If several processes (Puma
  workers, Sidekiq) use the same connection, keep the refresh token in a shared, consistent store and serialize refreshes with a
  lock: reusing an old refresh token revokes the connection for security.
- If `on_token_refresh` raises, the call fails with `token_persist_failed`; the new token stays in memory and the next call retries
  saving it. Don't call the same connection from inside the callback (the lock is not reentrant).
- Management endpoints (API keys, domains, contacts, broadcasts) cannot be called with a connection token; only sending, reading and
  discovery are available.
- When the customer closes their account in your app, call `connect.revoke(refresh_token: token)`.

## Deprecation warnings

If the API has deprecated this SDK version (`Deprecation` response header), the client prints a warning to stderr once per client.
The call itself is not affected. Deprecated versions and their sunset dates are listed in
[deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Never embed your API key or `client_secret` in browser or mobile code; even a `sending_access` key
  can send email. Store refresh tokens encrypted.
- **HTTPS enforced.** `base_url` and `web_url` must use `https`; plain `http` is accepted only for `localhost`, `*.localhost`,
  `127.0.0.0/8` and `[::1]` (local development). Anything else raises `ArgumentError` at construction time. TLS certificates are
  always verified; there is no option to turn that off.
- **Redirects refused.** The API never redirects, so a `3xx` response is not followed (that could leak `Authorization` to another
  host); it raises `Nafru::Email::Error` with `name == "unexpected_redirect"` and is not retried.
- **Input checks.** Path parameters are percent-encoded and an empty, `.` or `..` segment raises `ArgumentError` before any request;
  `idempotency_key` may not be empty or contain control characters (no header injection). Response bodies are capped at 10 MB
  (`response_too_large`).
- **Secrets redacted.** `inspect`, `to_s` and `pp` of `NafruEmail`, `NafruConnect`, connections and `ConnectionGrant` never show the
  API key, client secret or tokens (`[REDACTED]`); error messages never include them. Read the value explicitly
  (`grant.refresh_token`) when you store it.
- **Webhooks.** Verify against the **raw** request body (`request.raw_post`); comparison is constant-time, timestamps outside ±5
  minutes are rejected, missing headers return `false`, and at most 32 signatures per header are checked.
- **Reporting vulnerabilities.** Please don't open a public issue. Use GitHub
  [private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email security@nafru.com; see
  [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

Contributions are welcome; see [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md).

```sh
bundle install
bundle exec rake test
gem build nafru-email.gemspec
```

The version lives in one place, `lib/nafru_email/version.rb` (`VERSION`); the gemspec reads it from there.

## Troubleshooting

Every API failure raises `Nafru::Email::Error`; check `e.name`, `e.status_code` and `e.message`. Configuration mistakes raise
`ArgumentError` before any request is made.

- **`missing_api_key` / `invalid_api_key` / `unauthorized` (401/403).** The key is missing, wrong or revoked. `NafruEmail.new` with no
  argument reads `NAFRU_API_KEY`; if that is unset too it raises `ArgumentError` ("api_key gerekli"). Create a new key in the
  dashboard if it was revoked.
- **`forbidden` (403).** The key lacks permission: a `sending_access` key can send email but cannot list or manage resources, and
  may be restricted to one domain. Use a `full_access` key for management calls.
- **`validation_error` (422).** The request body is invalid. `e.errors` lists each problem as `{ field:, message: }`.
- **`rate_limit_exceeded` (429).** Retried automatically (up to `max_retries`, honoring `Retry-After`, capped at 8 s). If it still
  fails, `e.retry_after` tells you how many seconds to wait.
- **`timeout_error` / `application_error` with `status_code == nil`.** A network failure or timeout (`timeout:` defaults to 30 s).
  `GET`/`DELETE` are retried; a `POST`/`PATCH` is retried only with an `idempotency_key`, so pass one to make sending safe to retry.
- **`unexpected_redirect` (3xx).** The API never redirects. The `base_url` is probably wrong (missing `/api`, `http` → `https`
  upgrade, a login page) or a proxy is in between. Redirects are never followed or retried.
- **`ArgumentError: base_url https kullanmalı (http yalnız localhost için)`.** `base_url`/`web_url` must be `https`; `http` is only
  allowed for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **`response_too_large`.** The response body exceeded 10 MB. This points to a misbehaving proxy or the wrong `base_url`.
- **`connection_revoked` (Connect).** The customer disconnected your app or the refresh token is invalid or was reused. Ask the
  customer to connect again.
- **`token_persist_failed` (Connect).** Your `on_token_refresh` callback raised. The new refresh token is kept in memory and saving it
  is retried on the next call; fix the storage, because the old token is no longer valid.
- **`Webhook.verify` returns `false`.** Pass the **raw** body (`request.raw_post`, not re-serialized JSON). Use that webhook's own
  `whsec_…` signing secret. Pass the `svix-id`, `svix-timestamp` and `svix-signature` headers. Keep the server clock in sync
  (timestamps more than 5 minutes off are rejected).
- **Emails are not being sent.** With `NODE_ENV=development` the dev outbox is on: emails are written to `.nafru/emails/` and the
  paths printed instead of sending. Pass `dev_outbox: false` to send for real.

## Links

- API documentation: https://email.nafru.com
- Source and issues: https://github.com/nafrucom/nafru-email-sdks

Other official SDKs:

| Language             | Package                                                                 |
| -------------------- | ----------------------------------------------------------------------- |
| TypeScript / Node.js | [`@nafrucom/email`](https://www.npmjs.com/package/@nafrucom/email)      |
| Python               | [python](https://github.com/nafrucom/nafru-email-sdks/tree/main/python) |
| PHP                  | [php](https://github.com/nafrucom/nafru-email-sdks/tree/main/php)       |
| Ruby                 | [ruby](https://github.com/nafrucom/nafru-email-sdks/tree/main/ruby)     |
| Java                 | [java](https://github.com/nafrucom/nafru-email-sdks/tree/main/java)     |
| .NET (C#)            | [dotnet](https://github.com/nafrucom/nafru-email-sdks/tree/main/dotnet) |
| Go                   | [go](https://github.com/nafrucom/nafru-email-sdks/tree/main/go)         |
| Rust                 | [rust](https://github.com/nafrucom/nafru-email-sdks/tree/main/rust)     |
| Swift                | [swift](https://github.com/nafrucom/nafru-email-sdks/tree/main/swift)   |

## Support

- Questions and how-to: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (do not open a public issue)

More details are in [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md).

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/ruby/LICENSE).
