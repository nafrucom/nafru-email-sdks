# Nafru Email Python SDK

The official **Nafru Email Python SDK** (`nafru-email`) for the Nafru Email API, a transactional and marketing **email API**. Use it to
**send email from Python**, manage domains, contacts, templates and broadcasts, and verify **webhooks**. The API is **Resend-compatible**,
so request shapes, field names and errors match Resend. The SDK has zero dependencies: it uses only the standard library (urllib, hmac,
hashlib) and ships full type hints.

[![PyPI version](https://img.shields.io/pypi/v/nafru-email.svg)](https://pypi.org/project/nafru-email/)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/python/LICENSE)

## Requirements

Python 3.9 or later.

## Installation

```sh
pip install nafru-email
```

## Quick start: send an email

```python
from nafru_email import NafruEmail, NafruError

nafru = NafruEmail("nafru_...")  # or NafruEmail() to read the NAFRU_API_KEY environment variable
# Optional settings: NafruEmail("nafru_...", base_url="http://localhost:48787/api", max_retries=2, timeout=30, dev_outbox=False)
# base_url defaults to DEFAULT_BASE_URL (https://email.nafru.com/api).

try:
    data = nafru.emails.send(
        {
            "from": "Acme <hello@example.com>",
            "to": "jane@example.org",
            "subject": "Welcome",
            "html": "<p>Hello!</p>",
            "scheduled_at": "in 1 hour",  # optional: ISO 8601 or a relative expression, up to 30 days ahead
        },
        idempotency_key="signup-1042",  # retrying with the same key returns the same email
    )
    print(data["id"])
except NafruError as error:
    print(error.status_code, error.name, error.message)
```

Body fields use `snake_case` exactly as the API does (`reply_to`, `scheduled_at`, `first_name`); there is no conversion layer. Requests and
responses are `TypedDict`s (`nafru_email.types`), so they go in and come out as plain `dict`s.

## No sending in development

When `NODE_ENV=development`, `emails.send` and `emails.batch` (and `emails.send` on a connection client) **do not send** anything. Each email is
written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the same name, and the file paths and plain
text are printed to the console. The call returns a `dev_…` id. Change the folder with `dev_outbox="tmp/mail"`, or turn this off with
`dev_outbox=False`.

## Errors

Every failed call raises `NafruError`:

```python
error.status_code  # int | None — None on network errors and timeouts
error.name         # validation_error, not_found, rate_limit_exceeded, application_error, timeout_error, …
error.message
error.errors       # [{"field": ..., "message": ...}] — per-field details on 422
error.retry_after  # seconds, on 429
```

## Retries, timeouts and idempotency

- `429` is retried on every method, honoring `retry-after` (the request was rejected before being processed; the wait is capped at 8 s).
- `GET`/`DELETE` are retried on `5xx` and network errors (exponential backoff starting at 300 ms).
- `POST`/`PATCH` are **not** retried on server errors, because an email could go out twice; they are retried if you pass `idempotency_key`.
- Defaults: 2 retries (`max_retries`) and a 30 s timeout (`timeout`, in seconds).
- For tests or a proxy, pass your own transport with `transport=`: a function that takes an `HttpRequest` and returns an `HttpResponse`.

## Resources

|                      |                                                                                                                                   |
| -------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `emails`             | `send` `batch` `get` `list` `update` `cancel`                                                                                     |
| `domains`            | `create` `get` `list` `update` `remove` `verify`                                                                                  |
| `contacts`           | `create` `get` `list` `update` `remove`, `segments.{list,add,remove}`, `topics.{list,update}` (accepts an id or an email address) |
| `contact_properties` | `create` `get` `list` `update` `remove`                                                                                           |
| `segments`           | `create` `get` `list` `remove` `contacts`                                                                                         |
| `topics`             | `create` `get` `list` `update` `remove`                                                                                           |
| `broadcasts`         | `create` `get` `list` `update` `remove` `send` `cancel`                                                                           |
| `templates`          | `create` `get` `list` `update` `remove` `publish` `duplicate` `put_translation` `remove_translation` (id or alias)                |
| `brand`              | `get` `update`: workspace branding; `update` replaces the **whole** brand, so read it with `get` first                            |
| `webhooks`           | `create` `get` `list` `update` `remove`                                                                                           |
| `api_keys`           | `create` `list` `remove`                                                                                                          |
| `events`             | `send` `batch` `list`: custom events that trigger automations                                                                     |

## Pagination

Lists are cursor-based (`limit`, `after`, `before` keyword arguments). To walk every page:

```python
from functools import partial
from nafru_email import paginate

for contact in paginate(nafru.contacts.list, limit=100):
    print(contact["email"])

# Lists that take an id:
for topic in paginate(partial(nafru.contacts.topics.list, "jane@example.org")):
    print(topic["name"])
```

If a page fails, the generator raises `NafruError` instead of stopping silently.

## Sending with a template

```python
nafru.templates.create({
    "name": "Welcome",
    "alias": "welcome",
    "subject": "Welcome {{{NAME|friend}}}",
    "html": "<html><body><p>Hello {{{NAME|friend}}}</p></body></html>",
    "brand": {"mode": "inherit"},
})
nafru.templates.publish("welcome")

nafru.emails.send({
    "from": "Acme <hello@acme.example>",
    "to": "jane@example.org",
    "template": {"id": "welcome", "variables": {"NAME": "Jane"}},
})
```

## Recurring broadcasts and data sources

```python
nafru.broadcasts.create({
    "segment_id": "seg_1",
    "from": "Acme <hello@acme.example>",
    "html": "<p>This week's plan: {{{data.plan}}}</p>",
    "recurrence": {"type": "weekly", "days": [1], "time": "09:00"},  # or monthly{day, time}, interval{every_days, time}
    "data_source": {"type": "url", "url": "https://acme.example/weekly.json"},  # manual | url | webhook
})
nafru.broadcasts.update("b_1", {"recurrence": None})  # None clears a field; omitted fields stay unchanged
```

## Custom events

```python
nafru.events.send({
    "name": "plan_upgraded",
    "contact": {"email": "jane@example.org"},  # created if it does not exist
    "properties": {"plan": "pro", "seats": 3},
})
```

## Verifying webhook signatures

The server signs webhooks in the Svix/Standard Webhooks format. Use the **raw** body; parsed and re-serialized JSON breaks the signature.

```python
from nafru_email import verify_webhook

ok = verify_webhook(
    request.get_data(),  # raw body (bytes or str)
    {
        "id": request.headers["svix-id"],
        "timestamp": request.headers["svix-timestamp"],
        "signature": request.headers["svix-signature"],
    },
    os.environ["NAFRU_WEBHOOK_SECRET"],  # signing_secret from the webhooks.create response
)
if not ok:
    return "invalid signature", 400
```

Timestamps more than 5 minutes in the past or future are rejected (`tolerance_seconds`). During key rotation several signatures may be sent;
one valid signature is enough. A malformed `whsec_` secret raises `ValueError` (a configuration error).

## Connect with Nafru (for apps)

If you want your own product's customers to send from **their own** Nafru Email account, do not ask them to copy an API key: register your app
in Nafru Email (Developer → Apps) and use `NafruConnect`.

```python
import os
from nafru_email import NafruConnect

connect = NafruConnect(
    client_id=os.environ["NAFRU_CLIENT_ID"],
    client_secret=os.environ["NAFRU_CLIENT_SECRET"],  # server-side only
    # base_url is optional (defaults to https://email.nafru.com/api; locally "http://localhost:48787/api")
    # web_url: the consent screen; if omitted, the trailing /api is stripped from base_url
)

# 1) Redirect the customer. Store code_verifier and state in the session.
auth = connect.authorize_url(
    redirect_uri="https://myapp.example/nafru/callback",
    state=state,
    scopes=["emails.send", "templates.read", "senders.read", "connection.read"],
)
redirect(auth["url"])

# 2) On return, verify state and exchange the code for a connection.
grant = connect.exchange(code=code, code_verifier=auth["code_verifier"], redirect_uri=redirect_uri)
# Map grant.connection_id to the customer; store grant.refresh_token ENCRYPTED (repr() masks it).

# 3) Call on the customer's behalf. The access token is refreshed automatically; the refresh token CHANGES on every refresh.
connection = connect.connection(
    connection_id,
    refresh_token=load(connection_id),
    on_token_refresh=lambda tokens: save(connection_id, tokens.refresh_token),  # the old token is invalid once rotated, so persist it
)

status = connection.status()  # ready, missing: ['domain', 'sender', …], setup_url
connection.senders.list()
connection.templates.list()  # the customer's templates + your app's bundle
connection.emails.send({"from": sender, "to": to, "subject": "…", "template": {"id": "welcome", "variables": {}}})
```

- If the customer disconnected or the refresh token is invalid, `NafruError.name == "connection_revoked"`; ask the customer to reconnect.
- Concurrent threads using the same connection object share a single refresh (single flight). If several processes use the same connection,
  keep the refresh token in a shared, consistent store and serialize refreshes with a lock: reusing an old token revokes the connection for
  security.
- If `on_token_refresh` raises, the call raises `token_persist_failed`; the new token stays in memory and the next call retries saving it.
- Management endpoints cannot be called with a connection token; only sending, reading and discovery are available.
- When the customer closes their account: `connect.revoke(refresh_token=...)`.

## Deprecation warnings

When the API deprecates this SDK version, responses carry a `Deprecation` header; a warning is printed to stderr once per client (with the
sunset date and a details link when present). The call itself is not affected.
Deprecated versions are listed in [deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Never put the API key or client secret in browser or mobile code; even a `sending_access` key can send email.
- **HTTPS is enforced.** `base_url` and `web_url` must use `https`; plain `http` is accepted only for `localhost`, `*.localhost`,
  `127.0.0.0/8` and `[::1]` (local development). Certificate verification is always on and cannot be disabled.
- **Redirects are refused.** The API never redirects, so a `3xx` response raises `NafruError` with name `unexpected_redirect` instead of
  forwarding your `Authorization` header to another host.
- **Input checks.** Empty, `.` and `..` path parameters and `idempotency_key` values with control characters (CR/LF) raise
  `invalid_argument` before any request is sent. Response bodies are capped at 10 MB (`response_too_large`).
- **Secrets are redacted.** `repr()` of `NafruEmail`, `NafruConnect`, `ConnectionGrant`, `ConnectionTokens` and `HttpRequest` masks the API
  key, client secret and tokens (`nafru_****`); errors never include them.
- **Verify webhooks on the raw body.** Pass the exact bytes/string you received to `verify_webhook`; the comparison is constant-time and the
  timestamp must be within 5 minutes in either direction.
- **Reporting a vulnerability:** see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md). Report privately through
  [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email security@nafru.com. Please do not open a public issue.

## Development

```sh
uv run --with pytest pytest   # unit tests (no network, fake transport)
uv build                      # dist/ (sdist + wheel)
```

The single source of the version is `SDK_VERSION` in `src/nafru_email/__init__.py` (`pyproject.toml` reads it).

## Troubleshooting

Every failed call raises `NafruError`; check `error.name` first.

| `error.name` / symptom                                               | What it means and what to do                                                                                                                                                                                                             |
| -------------------------------------------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `unauthorized` / `invalid_api_key`                                   | The key is wrong or revoked, or `NafruEmail()` was called without a key and `NAFRU_API_KEY` is not set (that case raises `ValueError` at construction). Create a new key in the dashboard.                                               |
| `forbidden`                                                          | The key lacks permission, e.g. a `sending_access` key can send but cannot list or manage resources. Use a `full_access` key for management calls.                                                                                        |
| `validation_error`                                                   | The request body is invalid. `error.errors` lists each failing `field` and `message`.                                                                                                                                                    |
| `rate_limit_exceeded`                                                | Too many requests. The SDK already retried (`max_retries`, honoring `retry-after`); `error.retry_after` says how many seconds to wait.                                                                                                   |
| `timeout_error` / `application_error` with `status_code` `None`      | Network failure or timeout (`timeout`, default 30 s). `GET`/`DELETE` are retried automatically; a `POST` is retried only with an `idempotency_key`, so pass one to retry sends safely without duplicates.                                |
| `unexpected_redirect`                                                | The API never redirects: `base_url` is wrong (missing `/api`, wrong host) or a proxy redirects. Redirects are not followed so your key is not leaked.                                                                                    |
| `ValueError: base_url https kullanmalı (http yalnız localhost için)` | `base_url` / `web_url` must be `https`; plain `http` is allowed only for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.                                                                                                          |
| `response_too_large`                                                 | The response exceeded 10 MB, usually a misbehaving proxy or the wrong `base_url`.                                                                                                                                                        |
| `invalid_argument`                                                   | An empty, `.` or `..` id, or an `idempotency_key` that is empty or contains control characters.                                                                                                                                          |
| `connection_revoked` (Connect)                                       | The customer disconnected your app or the refresh token is invalid/reused. Ask the customer to connect again.                                                                                                                            |
| `token_persist_failed` (Connect)                                     | Your `on_token_refresh` callback raised. The new refresh token is kept in memory and saving is retried on the next call; fix storage before the process restarts.                                                                        |
| `verify_webhook` returns `False`                                     | Pass the **raw** request body (not re-serialized JSON), the endpoint's `whsec_…` signing secret, and the `svix-id`, `svix-timestamp`, `svix-signature` headers. Check the server clock: timestamps more than 5 minutes off are rejected. |
| Emails are not being sent                                            | `NODE_ENV=development` turns on the dev outbox: emails are written to `.nafru/emails/` instead of sent. Pass `dev_outbox=False` or unset `NODE_ENV`.                                                                                     |

## Links

| Language   | Package                                   | Source                                                                  |
| ---------- | ----------------------------------------- | ----------------------------------------------------------------------- |
| TypeScript | `@nafrucom/email` (npm)                   | [npm](https://www.npmjs.com/package/@nafrucom/email)                    |
| Python     | `nafru-email` (PyPI)                      | [python](https://github.com/nafrucom/nafru-email-sdks/tree/main/python) |
| Go         | `github.com/nafrucom/nafru-email-sdks/go` | [go](https://github.com/nafrucom/nafru-email-sdks/tree/main/go)         |
| PHP        | `nafrucom/email` (Packagist)              | [php](https://github.com/nafrucom/nafru-email-sdks/tree/main/php)       |
| Ruby       | `nafru-email` (RubyGems)                  | [ruby](https://github.com/nafrucom/nafru-email-sdks/tree/main/ruby)     |
| Java       | `com.nafru:nafru-email` (Maven Central)   | [java](https://github.com/nafrucom/nafru-email-sdks/tree/main/java)     |
| .NET       | `Nafru.Email` (NuGet)                     | [dotnet](https://github.com/nafrucom/nafru-email-sdks/tree/main/dotnet) |
| Rust       | `nafru-email` (crates.io)                 | [rust](https://github.com/nafrucom/nafru-email-sdks/tree/main/rust)     |
| Swift      | SwiftPM                                   | [swift](https://github.com/nafrucom/nafru-email-sdks/tree/main/swift)   |

- API documentation: [https://email.nafru.com](https://email.nafru.com)
- All SDKs: [github.com/nafrucom/nafru-email-sdks](https://github.com/nafrucom/nafru-email-sdks)

## Support

- Questions and ideas: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never in a public issue)

See [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md) for details and [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md) to contribute.

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/python/LICENSE).
