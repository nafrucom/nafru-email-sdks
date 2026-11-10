# Nafru Email .NET SDK

The official **Nafru Email .NET SDK** (`Nafru.Email`) for C# and .NET 8+. Nafru Email is a transactional and marketing
**email API** with a Resend-compatible surface. Use this C# SDK to send email from .NET (transactional email, scheduled
email, templates, batch sends), manage domains, contacts, segments and broadcasts, verify webhooks, and let your own
customers send from their Nafru Email account with "Connect with Nafru" (OAuth). It has no dependencies: just `HttpClient`
and `System.Text.Json`.

[![NuGet](https://img.shields.io/nuget/v/Nafru.Email.svg)](https://www.nuget.org/packages/Nafru.Email)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/dotnet/LICENSE)

## Requirements

- .NET 8 or later

## Installation

```sh
dotnet add package Nafru.Email
```

## Quick start: send an email

```csharp
using Nafru.Email;

var nafru = new NafruEmail("nafru_..."); // or new NafruEmail() to read the NAFRU_API_KEY environment variable

var sent = await nafru.Emails.SendAsync(
    new SendEmailInput
    {
        From = "Acme <hello@example.com>",
        To = ["ali@example.org"],
        Subject = "Welcome",
        Html = "<p>Hello!</p>",
        ScheduledAt = "in 1 hour" // optional: ISO 8601 or a relative expression, up to 30 days ahead
    },
    idempotencyKey: "signup-1042"); // retrying with the same key returns the same email

Console.WriteLine(sent.Id);
```

Properties are `PascalCase` in C# and are sent as `snake_case` on the wire, just like the API (`ReplyTo` → `reply_to`).
Every method accepts a `CancellationToken`.

### Clearing fields in PATCH requests

Clearable fields on update inputs are typed `Optional<T>`: a field you don't set is not sent (left unchanged), and a field
set to `null` is cleared.

```csharp
await nafru.Contacts.UpdateAsync("ali@example.org", new UpdateContactInput { FirstName = null, LastName = "Kaya" });
// body: {"first_name":null,"last_name":"Kaya"}
```

## No sending in development

When `NODE_ENV=development`, `Emails.SendAsync` and `Emails.BatchAsync` (and `Emails.SendAsync` on a connection client)
**do not send** email. Each email is written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html`
file with the same name, and the file paths and plain text are printed to the console. The response comes back with a
`dev_…` id. Change the folder with `DevOutbox = "tmp/mail"`, or turn it off with `DevOutbox = ""`.

## Errors

Every failed call throws `NafruException`:

```csharp
try
{
    await nafru.Emails.GetAsync("em_123");
}
catch (NafruException error)
{
    // error.StatusCode: int? (null on network errors/timeouts)
    // error.Name: validation_error, not_found, rate_limit_exceeded, application_error, timeout_error, …
    // error.Message, error.Errors (field details on 422), error.RetryAfter (seconds on 429)
}
```

## Retries, idempotency and timeouts

- `429` is retried on every method, honoring `retry-after` (the request was rejected before being processed).
- `5xx` and network errors are retried for `GET`/`DELETE`.
- `POST`/`PATCH` are **not** retried on server errors, because the email could be sent twice; they are retried if you
  pass an `idempotencyKey`.
- Defaults: 2 retries (`MaxRetries`), 30 s timeout (`Timeout`). Backoff starts at 300 ms and doubles, up to 8 s.
- Pass your own `HttpClient` via `HttpClient = …` (proxy, tests); otherwise a shared client is used. The shared client
  never follows redirects; with your own client, disabling redirects (`AllowAutoRedirect = false` on its handler) is your
  responsibility. Any 3xx that reaches the SDK fails with `unexpected_redirect` and is never retried.

All settings are optional and go in a `NafruEmailOptions` as the second argument:

```csharp
var nafru = new NafruEmail("nafru_...", new NafruEmailOptions
{
    BaseUrl = "http://localhost:48787/api", // default: NafruEmail.DefaultBaseUrl (https://email.nafru.com/api)
    MaxRetries = 3,
    Timeout = TimeSpan.FromSeconds(10),
    DevOutbox = "tmp/mail"
});
```

## Resources

|                     |                                                                                                                     |
| ------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `Emails`            | `Send` `Batch` `Get` `List` `Update` `Cancel`                                                                       |
| `Domains`           | `Create` `Get` `List` `Update` `Remove` `Verify`                                                                    |
| `Contacts`          | `Create` `Get` `List` `Update` `Remove`, `Segments.{List,Add,Remove}`, `Topics.{List,Update}` (by id or email)      |
| `ContactProperties` | `Create` `Get` `List` `Update` `Remove`                                                                             |
| `Segments`          | `Create` `Get` `List` `Remove` `Contacts`                                                                           |
| `Topics`            | `Create` `Get` `List` `Update` `Remove`                                                                             |
| `Broadcasts`        | `Create` `Get` `List` `Update` `Remove` `Send` `Cancel`                                                             |
| `Templates`         | `Create` `Get` `List` `Update` `Remove` `Publish` `Duplicate` `PutTranslation` `RemoveTranslation` (by id or alias) |
| `Brand`             | `Get` `Update`: workspace brand (logo, colors, font, footer)                                                        |
| `Webhooks`          | `Create` `Get` `List` `Update` `Remove`                                                                             |
| `ApiKeys`           | `Create` `List` `Remove`                                                                                            |
| `Events`            | `Send` `Batch` `List`: custom events that trigger automations                                                       |

Method names end in `…Async` (`SendAsync`, `ListAsync`, …).

## Pagination

Lists are cursor-based (`Limit`, `After`, `Before`). To iterate over everything:

```csharp
await foreach (var contact in NafruPagination.PaginateAsync(nafru.Contacts.ListAsync, new ListContactsQuery { Limit = 100 }))
{
    Console.WriteLine(contact.Email);
}
```

If a page fails, the loop throws `NafruException`; it never stops silently.

## Recurring broadcasts and data sources

```csharp
await nafru.Broadcasts.CreateAsync(new CreateBroadcastInput
{
    SegmentId = "seg_123",
    From = "Acme <newsletter@example.com>",
    TemplateId = "weekly-digest",
    Recurrence = new WeeklyRecurrence { Days = [1], Time = "09:00" }, // or MonthlyRecurrence / IntervalRecurrence
    DataSource = new UrlDataSourceInput { Url = "https://example.com/digest.json" }, // {{{data.*}}} is fetched from here at send time
    Send = true // for a recurring broadcast this activates the schedule instead of sending now
});

// Send null to remove the recurrence (unset fields are left unchanged):
await nafru.Broadcasts.UpdateAsync("bc_123", new UpdateBroadcastInput { Recurrence = null });
```

In responses, `Recurrence` and `DataSource` are deserialized into their subtypes (`WeeklyRecurrence`, `UrlDataSource`, …);
an unknown `type` falls back to the base type instead of throwing.

## Templates and brand

```csharp
await nafru.Templates.CreateAsync(new CreateTemplateInput
{
    Name = "Welcome",
    Alias = "welcome",
    Subject = "Welcome {{{NAME|friend}}}",
    Html = "<html><body><p>Hello {{{NAME|friend}}}</p></body></html>",
    Brand = new TemplateBrand { Mode = "inherit" } // inherit the workspace brand
});
await nafru.Templates.PublishAsync("welcome");

await nafru.Emails.SendAsync(new SendEmailInput
{
    From = "Acme <hello@acme.example>",
    To = ["ali@example.org"],
    Template = new EmailTemplate { Id = "welcome", Variables = new Dictionary<string, object> { ["NAME"] = "Ali" } }
});
```

`Brand.UpdateAsync` replaces the **entire** brand; any field you don't send becomes "not set", so read it with
`Brand.GetAsync` first and modify that. A template's `Brand.Mode`: `inherit` (brand as is), `custom` (brand + `Override`),
`none` (nothing added; the default for templates created through the API).

## Custom events

```csharp
await nafru.Events.SendAsync(new SendEventInput
{
    Name = "plan_upgraded",
    Contact = new EventContact { Email = "ali@example.org" }, // created if the contact doesn't exist
    Properties = new Dictionary<string, object?> { ["plan"] = "pro", ["seats"] = 3 }
});
```

## Verifying webhook signatures

The server signs webhooks in the Svix / Standard Webhooks format. Use the **raw** body; JSON that has been parsed and
re-serialized will break the signature.

```csharp
// ASP.NET Core
app.MapPost("/webhooks/nafru", async (HttpRequest request) =>
{
    var payload = await new StreamReader(request.Body).ReadToEndAsync();
    var ok = NafruWebhook.Verify(
        payload,
        id: request.Headers["svix-id"]!,
        timestamp: request.Headers["svix-timestamp"]!,
        signature: request.Headers["svix-signature"]!,
        secret: Environment.GetEnvironmentVariable("NAFRU_WEBHOOK_SECRET")!); // SigningSecret from the Webhooks.CreateAsync response
    return ok ? Results.Ok() : Results.BadRequest("invalid signature");
});
```

Returns `false` if the timestamp is more than 5 minutes in the past or future (`toleranceSeconds`). During key rotation,
when several signatures arrive, one valid signature is enough. A malformed `secret` (not starting with `whsec_`) throws
`ArgumentException`.

## Connect with Nafru (for apps)

If you want your product's customers to send from **their own** Nafru Email account, don't ask them to copy an API key:
register your app in Nafru Email (Developer → Apps) and use `NafruConnect`.

```csharp
var connect = new NafruConnect(new NafruConnectOptions
{
    ClientId = Environment.GetEnvironmentVariable("NAFRU_CLIENT_ID")!,
    ClientSecret = Environment.GetEnvironmentVariable("NAFRU_CLIENT_SECRET")! // server-side only
    // BaseUrl: optional, defaults to https://email.nafru.com/api (locally http://localhost:48787/api)
    // WebUrl: the consent screen; if omitted, the trailing /api is stripped from BaseUrl
});

// 1) Redirect the customer. Store the CodeVerifier and state in the session.
var authorize = connect.AuthorizeUrl(new AuthorizeUrlInput
{
    RedirectUri = "https://myapp.example/nafru/callback",
    State = state,
    Scopes = [AppScope.EmailsSend, AppScope.TemplatesRead, AppScope.SendersRead, AppScope.ConnectionRead]
});

// 2) On return, verify the state and exchange the code for a connection.
var grant = await connect.ExchangeAsync(new ExchangeInput { Code = code, CodeVerifier = codeVerifier, RedirectUri = redirectUri });
// Map grant.ConnectionId to the customer; store grant.RefreshToken ENCRYPTED.

// 3) Call on the customer's behalf. The access token is refreshed automatically; the refresh token CHANGES on every refresh.
var connection = connect.Connection(connectionId, new ConnectionOptions
{
    RefreshToken = await LoadAsync(connectionId),
    OnTokenRefresh = tokens => SaveAsync(connectionId, tokens.RefreshToken) // the old token is invalid until this is persisted
});

var status = await connection.StatusAsync(); // Ready, Missing: ["domain","sender",…], SetupUrl
await connection.Senders.ListAsync();
await connection.Templates.ListAsync(); // the customer's templates + your app's bundle
await connection.Emails.SendAsync(new SendEmailInput { From = from, To = [to], Template = new EmailTemplate { Id = "welcome" } });
```

- If the customer disconnected or the refresh token is invalid, you get `NafruException.Name == "connection_revoked"`;
  ask the customer to reconnect.
- Concurrent calls on the same connection object share a single refresh (single flight). If several processes/instances
  use the same connection, keep the refresh token in a shared, consistent store and serialize refreshes with a lock:
  reusing an old refresh token revokes the connection for security.
- If `OnTokenRefresh` throws, the call fails with `token_persist_failed`; the new token stays in memory and saving it is
  retried on the next call.
- If the server responds `401 invalid_token`, the token is refreshed once and the request is retried.
- Management endpoints (API keys, domains, contacts, broadcasts) can't be called with a connection token; only sending,
  reading and discovery are available.
- When the customer closes their account, call `await connect.RevokeAsync(refreshToken)`.

## Deprecation warnings

If the server has deprecated this SDK version (`Deprecation` response header), a warning is printed to stderr once per
client; the call itself does not fail. Deprecated versions are listed in
[deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Don't embed your API key or client secret in client apps (desktop, mobile, Blazor
  WebAssembly). Even a `sending_access` key can send email.
- **HTTPS enforced.** `BaseUrl` and `WebUrl` must use `https`; plain `http` is accepted only for `localhost`,
  `*.localhost`, `127.0.0.0/8` and `[::1]`. Certificate verification is never disabled.
- **Redirects refused.** The API never redirects; a 3xx fails with `unexpected_redirect` so your `Authorization` header
  can't leak to another host.
- **Secrets redacted.** `ToString()` of options, grants, token and webhook-secret records prints `[REDACTED]`, and
  exceptions never contain keys or tokens. Path segments `""`, `.` and `..` and idempotency keys with control characters
  are rejected before any request; response bodies are capped at 10 MB (`response_too_large`).
- **Verify webhooks on the raw body** with `NafruWebhook.Verify` (constant-time comparison, 5-minute tolerance both ways).
- **Reporting vulnerabilities:** see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md). Report privately via
  [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or
  security@nafru.com; please don't open a public issue.

## Development

```sh
dotnet test                                            # unit tests
dotnet pack src/Nafru.Email -c Release -o artifacts    # NuGet package
```

## Troubleshooting

Every failed call throws `NafruException`; check `Name` (and `StatusCode`).

- **`missing_api_key` / `invalid_api_key`** (401 / 403): no key, a wrong key, or a revoked key. `new NafruEmail()` reads
  `NAFRU_API_KEY`; if it isn't set, the constructor throws `ArgumentException` ("apiKey gerekli") before any request.
- **`restricted_api_key` / `forbidden`** (403): the key lacks permission. A `sending_access` key can only send email; it
  can't list or manage resources. Create a `full_access` key for management calls.
- **`validation_error`** (422): the request body is invalid. `Errors` lists each field (`Field`, `Message`).
- **`rate_limit_exceeded`** (429): already retried automatically (`MaxRetries`, honoring `retry-after`). If it still
  fails, back off for `RetryAfter` seconds.
- **`timeout_error` / `application_error`** (`StatusCode == null`): network failure or timeout (`Timeout`, default 30 s).
  `GET`/`DELETE` are retried; `POST`/`PATCH` are retried only with an `idempotencyKey`, so pass one to make sends safe to
  retry without duplicates.
- **`unexpected_redirect`** (3xx): the API never redirects. Usually a wrong `BaseUrl` (e.g. missing `/api`, `http` → `https`
  redirect) or a proxy in between. Point `BaseUrl` at the API root, e.g. `https://email.nafru.com/api`.
- **"baseUrl must use https (http is allowed only for localhost)"**: `ArgumentException` at construction. Use `https`;
  plain `http` only works for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **`response_too_large`**: the response body exceeded 10 MB, which the API never sends; check for a proxy or a wrong
  `BaseUrl`.
- **`ArgumentException` on a path or idempotency key**: an id/email/alias/locale was empty, `.` or `..`, or an
  `idempotencyKey` was empty or contained control characters (CR, LF, …).
- **`connection_revoked`** (Connect): the customer disconnected the app or the refresh token is invalid/reused. Ask the
  customer to reconnect.
- **`token_persist_failed`** (Connect): your `OnTokenRefresh` threw. The new refresh token is kept in memory and saving
  is retried on the next call; fix the store, or the connection is lost after a restart.
- **`NafruWebhook.Verify` returns `false`**: pass the **raw** request body (not re-serialized JSON); use that webhook's
  `whsec_…` signing secret; pass the `svix-id`, `svix-timestamp` and `svix-signature` headers unchanged; make sure the
  server clock is within 5 minutes (`toleranceSeconds`).
- **Emails are not being sent**: with `NODE_ENV=development` the dev outbox is on; emails are written to
  `.nafru/emails/` and the path is printed instead of sending. Set `DevOutbox = ""` (or unset `NODE_ENV`) to send.

## Support

- Questions and how-to: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md), never a public issue

More in [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md). Contributions: [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md).

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

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/dotnet/LICENSE).
