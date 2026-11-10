# Nafru Email SDKs

**Official client libraries for the [Nafru Email](https://email.nafru.com) API.** Send transactional and marketing email,
manage contacts, domains, templates and broadcasts, and verify webhooks from **TypeScript / JavaScript, Python, Go, PHP,
Ruby, Java, .NET (C#), Rust and Swift**.

The Nafru Email API is **Resend-compatible**: the same request shapes, field names (`snake_case`) and error format. If you
already use Resend, you can switch by changing the base URL and API key; these SDKs add Nafru-only features on top
(custom events, brand, template translations, recurring broadcasts, "Connect with Nafru" OAuth).

[![npm](https://img.shields.io/npm/v/@nafrucom/email?label=npm)](https://www.npmjs.com/package/@nafrucom/email)
[![PyPI](https://img.shields.io/pypi/v/nafru-email?label=pypi)](https://pypi.org/project/nafru-email/)
[![Go Reference](https://pkg.go.dev/badge/github.com/nafrucom/nafru-email-sdks/go.svg)](https://pkg.go.dev/github.com/nafrucom/nafru-email-sdks/go)
[![Packagist](https://img.shields.io/packagist/v/nafrucom/email?label=packagist)](https://packagist.org/packages/nafrucom/email)
[![Gem](https://img.shields.io/gem/v/nafru-email?label=gem)](https://rubygems.org/gems/nafru-email)
[![Maven Central](https://img.shields.io/maven-central/v/com.nafru/nafru-email?label=maven)](https://central.sonatype.com/artifact/com.nafru/nafru-email)
[![NuGet](https://img.shields.io/nuget/v/Nafru.Email?label=nuget)](https://www.nuget.org/packages/Nafru.Email)
[![crates.io](https://img.shields.io/crates/v/nafru-email?label=crates.io)](https://crates.io/crates/nafru-email)
[![SwiftPM](https://img.shields.io/badge/SwiftPM-compatible-orange)](swift/README.md)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue)](LICENSE)

## Contents

- [Installation](#installation)
- [Quick start](#quick-start)
- [Features](#features)
- [Concepts](#concepts): authentication, errors, retries & idempotency, pagination, webhooks, Connect with Nafru,
  local development
- [Versioning and deprecation](#versioning-and-deprecation)
- [FAQ](#faq)
- [Security](#security) · [Support](#support)

## Installation

| Language                   | Package                                   | Install                                                                        | Docs                                                 |
| -------------------------- | ----------------------------------------- | ------------------------------------------------------------------------------ | ---------------------------------------------------- |
| TypeScript / JavaScript    | `@nafrucom/email`                         | `npm install @nafrucom/email`                                                  | [npm](https://www.npmjs.com/package/@nafrucom/email) |
| Python ≥ 3.9               | `nafru-email`                             | `pip install nafru-email`                                                      | [python/](python/README.md)                          |
| Go ≥ 1.21                  | `github.com/nafrucom/nafru-email-sdks/go` | `go get github.com/nafrucom/nafru-email-sdks/go`                               | [go/](go/README.md)                                  |
| PHP ≥ 8.1                  | `nafrucom/email`                          | `composer require nafrucom/email`                                              | [php/](php/README.md)                                |
| Ruby ≥ 3.1                 | `nafru-email`                             | `gem install nafru-email`                                                      | [ruby/](ruby/README.md)                              |
| Java ≥ 17                  | `com.nafru:nafru-email`                   | `implementation("com.nafru:nafru-email:0.1.1")`                                | [java/](java/README.md)                              |
| .NET 8+ (C#, F#)           | `Nafru.Email`                             | `dotnet add package Nafru.Email`                                               | [dotnet/](dotnet/README.md)                          |
| Rust                       | `nafru-email`                             | `cargo add nafru-email`                                                        | [rust/](rust/README.md)                              |
| Swift (iOS 15+, macOS 12+) | `NafruEmail`                              | `.package(url: "https://github.com/nafrucom/nafru-email-sdks", from: "0.1.1")` | [swift/](swift/README.md)                            |

Every SDK has the same feature set and is released with the **same version number on the same day**.

## Quick start

Create an API key in the Nafru Email dashboard and keep it on your server (never ship it to a browser or mobile app).
Each example sends one email; `idempotencyKey` makes a retried request return the same email instead of sending twice.

<details open>
<summary><b>TypeScript / JavaScript</b> (Node ≥ 18, Bun, Deno, Cloudflare Workers)</summary>

```ts
import { NafruEmail } from '@nafrucom/email'

const nafru = new NafruEmail('nafru_123')

const { data, error } = await nafru.emails.send(
  { from: 'Acme <hello@example.com>', to: 'user@example.org', subject: 'Welcome', html: '<p>Hello!</p>' },
  { idempotencyKey: 'signup-1042' }
)
if (error) console.error(error.statusCode, error.name, error.message)
else console.log(data.id)
```

</details>

<details>
<summary><b>Python</b></summary>

```python
import os
from nafru_email import NafruEmail, NafruError

nafru = NafruEmail("nafru_123")  # or NafruEmail(), which reads NAFRU_API_KEY

try:
    email = nafru.emails.send(
        {"from": "Acme <hello@example.com>", "to": "user@example.org", "subject": "Welcome", "html": "<p>Hello!</p>"},
        idempotency_key="signup-1042",
    )
    print(email["id"])
except NafruError as error:
    print(error.status_code, error.name, error.message)
```

</details>

<details>
<summary><b>Go</b></summary>

```go
client, err := nafruemail.NewClient("nafru_123") // "" reads NAFRU_API_KEY
if err != nil {
	log.Fatal(err)
}
sent, err := client.Emails.Send(ctx, &nafruemail.SendEmailInput{
	From:    "Acme <hello@example.com>",
	To:      []string{"user@example.org"},
	Subject: "Welcome",
	HTML:    "<p>Hello!</p>",
}, nafruemail.SendEmailOptions{IdempotencyKey: "signup-1042"})
if err != nil {
	log.Fatal(err) // *nafruemail.Error carries StatusCode, Name, Message
}
fmt.Println(sent.ID)
```

</details>

<details>
<summary><b>PHP</b></summary>

```php
use Nafru\Email\NafruEmail;
use Nafru\Email\NafruException;

$nafru = new NafruEmail('nafru_123'); // or new NafruEmail(), which reads NAFRU_API_KEY

try {
    $email = $nafru->emails->send(
        ['from' => 'Acme <hello@example.com>', 'to' => 'user@example.org', 'subject' => 'Welcome', 'html' => '<p>Hello!</p>'],
        idempotencyKey: 'signup-1042',
    );
    echo $email['id'];
} catch (NafruException $e) {
    error_log("{$e->statusCode} {$e->name} {$e->getMessage()}");
}
```

</details>

<details>
<summary><b>Ruby</b></summary>

```ruby
require "nafru_email"

nafru = NafruEmail.new("nafru_123") # or NafruEmail.new, which reads NAFRU_API_KEY

email = nafru.emails.send(
  { from: "Acme <hello@example.com>", to: "user@example.org", subject: "Welcome", html: "<p>Hello!</p>" },
  idempotency_key: "signup-1042"
)
puts email[:id]
```

</details>

<details>
<summary><b>Java</b></summary>

```java
NafruEmail nafru = new NafruEmail("nafru_123"); // or new NafruEmail(), which reads NAFRU_API_KEY

var sent = nafru.emails().send(
        new SendEmailInput()
                .from("Acme <hello@example.com>")
                .to("user@example.org")
                .subject("Welcome")
                .html("<p>Hello!</p>"),
        "signup-1042"); // Idempotency-Key
System.out.println(sent.id());
```

</details>

<details>
<summary><b>C# / .NET</b></summary>

```csharp
using Nafru.Email;

var nafru = new NafruEmail("nafru_123"); // or new NafruEmail(), which reads NAFRU_API_KEY

var sent = await nafru.Emails.SendAsync(
    new SendEmailInput { From = "Acme <hello@example.com>", To = ["user@example.org"], Subject = "Welcome", Html = "<p>Hello!</p>" },
    idempotencyKey: "signup-1042");
Console.WriteLine(sent.Id);
```

</details>

<details>
<summary><b>Rust</b></summary>

```rust
use nafru_email::{NafruEmail, SendEmailInput, SendEmailOptions};

let nafru = NafruEmail::new("nafru_123")?; // "" reads NAFRU_API_KEY

let sent = nafru
    .emails
    .send(
        &SendEmailInput {
            from: Some("Acme <hello@example.com>".into()),
            to: vec!["user@example.org".into()],
            subject: Some("Welcome".into()),
            html: Some("<p>Hello!</p>".into()),
            ..Default::default()
        },
        SendEmailOptions::idempotency_key("signup-1042"),
    )
    .await?;
println!("{}", sent.id);
```

</details>

<details>
<summary><b>Swift</b></summary>

```swift
import NafruEmail

let nafru = try NafruEmail("nafru_123") // or NafruEmail(), which reads NAFRU_API_KEY

let sent = try await nafru.emails.send(
    SendEmailInput(from: "Acme <hello@example.com>", to: ["user@example.org"], subject: "Welcome", html: "<p>Hello!</p>"),
    idempotencyKey: "signup-1042"
)
print(sent.id)
```

</details>

## Features

| Area                   | What you can do                                                                                                                                                                                                                        |
| ---------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| **Emails**             | Send single or batch (up to 100) emails, HTML / text / template bodies, attachments, tags, `cc` / `bcc` / `reply_to`, scheduled sending (`scheduled_at`, ISO 8601 or natural language like `in 1 hour`), reschedule, cancel, get, list |
| **Domains**            | Add sending domains, read DNS records (SPF, DKIM, DMARC), trigger verification, update tracking settings                                                                                                                               |
| **Contacts**           | Create, update, delete and list contacts (by id or email address), custom contact properties, segment membership, topic subscriptions (opt-in / opt-out)                                                                               |
| **Segments & topics**  | Static and dynamic audiences, subscription topics for preference centers                                                                                                                                                               |
| **Broadcasts**         | Draft, schedule, send and cancel campaigns; recurring broadcasts (weekly, monthly, every N days) with per-send `data` from a URL or webhook                                                                                            |
| **Templates**          | Create, update, publish and duplicate templates; per-locale translations; workspace brand (logo, colors, fonts, footer)                                                                                                                |
| **Events**             | Send custom events (single or batch) to trigger automations                                                                                                                                                                            |
| **Webhooks**           | Manage endpoints and verify signatures (Svix / Standard Webhooks compatible)                                                                                                                                                           |
| **API keys**           | Create, list and revoke keys with scoped access                                                                                                                                                                                        |
| **Connect with Nafru** | OAuth 2.0 + PKCE flow so your SaaS can send on behalf of your customers' Nafru accounts, with automatic token refresh                                                                                                                  |

## Concepts

### Authentication

API-key clients send `Authorization: Bearer <key>`. The default endpoint is `https://email.nafru.com/api`; pass a base URL
only for self-hosted or local development (`http://localhost:48787/api`).

### Errors

Every SDK exposes the same error fields, idiomatically (a `{ data, error }` result in TypeScript; an exception or error
value elsewhere):

| Field        | Meaning                                                                                                                                            |
| ------------ | -------------------------------------------------------------------------------------------------------------------------------------------------- |
| `statusCode` | HTTP status; empty for network failures and timeouts                                                                                               |
| `name`       | Machine-readable name: `validation_error`, `not_found`, `rate_limit_exceeded`, `unauthorized`, `conflict`, `timeout_error`, `application_error`, … |
| `message`    | Human-readable message                                                                                                                             |
| `errors`     | Per-field validation errors (`field`, `message`)                                                                                                   |
| `retryAfter` | Seconds to wait, from the `Retry-After` header on `429`                                                                                            |

### Retries, timeouts and idempotency

- Requests time out after 30 seconds (configurable).
- Up to 2 automatic retries (configurable, `0` disables) with exponential backoff capped at 8 seconds; `Retry-After` is
  honored.
- `429 Too Many Requests` is always retried. `5xx` and network errors are retried only for safe requests: `GET`, `DELETE`,
  or any request carrying an **`Idempotency-Key`**. A `POST` without a key is never retried, so an email is never sent
  twice by the SDK.

### Pagination

List endpoints are cursor-based (`limit`, `after`, `before`) and return `{ object: "list", data, has_more }`. Every SDK ships
a `paginate` helper that walks all pages for you and stops on the first error.

### Webhooks

Nafru signs webhook deliveries the same way as Svix / Standard Webhooks (`svix-id`, `svix-timestamp`, `svix-signature`
headers, HMAC-SHA256 with a `whsec_…` secret, 5-minute tolerance, constant-time comparison). Every SDK has a
`verifyWebhook` function; always pass the **raw** request body. All SDKs are tested against the same shared vector,
[`webhook-test-vector.json`](webhook-test-vector.json).

### Connect with Nafru (OAuth)

Building a product that sends email for your own customers? Instead of asking them to paste an API key, use the
"Connect with Nafru" flow: `authorizeUrl` (PKCE S256 + `state`) → redirect → `exchange` the code for a long-lived
connection → call `connection(id, { refreshToken, onTokenRefresh })`. Access tokens refresh automatically, concurrent
calls share a single refresh, and the rotated refresh token is handed to your `onTokenRefresh` callback to store.

### Local development: no email is sent

When `NODE_ENV=development`, `emails.send` and `emails.batch` do **not** send. Each email is written to `.nafru/emails/` as
`.txt` (headers + text) and `.html`, and the file paths are printed. Change the folder with the `devOutbox` option or
turn it off with `devOutbox: false`.

## Versioning and deprecation

- All SDKs follow [Semantic Versioning](https://semver.org) and share **one version number**. A release tag `vX.Y.Z`
  publishes every language at once.
- When a version is deprecated it is listed in [`deprecations.json`](deprecations.json). The API then answers that SDK
  version with `Deprecation`, `Sunset` and `Link` headers, and every SDK prints a one-time warning; requests keep working
  until the sunset date.

## FAQ

**Is Nafru Email compatible with Resend?** Yes. The API mirrors Resend's endpoints and payloads; the official Resend SDKs
work by pointing them at `https://email.nafru.com/api`. These SDKs add Nafru-specific endpoints and OAuth.

**Can I use these SDKs in the browser or a mobile app?** Not with an API key; any key can send email. Call the API from
your server. Mobile and desktop apps should go through your backend or use Connect with Nafru tokens kept server-side.

**Where is the source?** This repository is published automatically from the Nafru Email monorepo on every release.
Please open issues here.

## Security

Report vulnerabilities privately through [GitHub](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or
**security@nafru.com**. See [SECURITY.md](SECURITY.md) for our disclosure policy, response times and how the SDKs protect
your keys: HTTPS only, redirects refused, certificate verification always on, secrets redacted from logs, 10 MB response
cap, constant-time webhook verification.

## Support

| You want to…                                          | Go to                                                                           |
| ----------------------------------------------------- | ------------------------------------------------------------------------------- |
| Ask a question                                        | [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)  |
| Report a bug or request a feature                     | [GitHub Issues](https://github.com/nafrucom/nafru-email-sdks/issues/new/choose) |
| Get help with your account, billing or deliverability | **destek@nafru.com**                                                            |
| Report a vulnerability                                | [SECURITY.md](SECURITY.md) — privately, never in a public issue                 |

Every SDK README has a **Troubleshooting** section. See [SUPPORT.md](SUPPORT.md) and [CONTRIBUTING.md](CONTRIBUTING.md).

## License

[MIT](LICENSE) © Nafru
