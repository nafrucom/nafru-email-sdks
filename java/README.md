# Nafru Email Java SDK

The official **Nafru Email Java SDK** lets you send email from Java (Spring, Jakarta EE, Android back ends, Kotlin) through the Nafru
Email API. Use it for transactional email (sign-up confirmations, password resets, receipts) and marketing broadcasts, to manage
contacts, templates and domains, to trigger automations with custom events, and to verify webhooks. The email API is
Resend-compatible, so request and response shapes will feel familiar if you are coming from Resend.

[![Maven Central](https://img.shields.io/maven-central/v/com.nafru/nafru-email)](https://central.sonatype.com/artifact/com.nafru/nafru-email)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/java/LICENSE)

## Requirements

- Java 17 or later
- Uses `java.net.http.HttpClient`; the only runtime dependency is Jackson Databind.

## Installation

```kotlin
// Gradle (Kotlin DSL)
implementation("com.nafru:nafru-email:0.1.1")
```

```xml
<!-- Maven -->
<dependency>
  <groupId>com.nafru</groupId>
  <artifactId>nafru-email</artifactId>
  <version>0.1.1</version>
</dependency>
```

## Quick start: send an email

```java
import com.nafru.email.NafruEmail;
import com.nafru.email.model.SendEmailInput;

NafruEmail nafru = new NafruEmail("nafru_...");
// new NafruEmail() reads the key from the NAFRU_API_KEY environment variable.
// Other settings go through the builder (all optional; baseUrl defaults to NafruEmail.DEFAULT_BASE_URL, https://email.nafru.com/api):
// NafruEmail nafru = NafruEmail.builder().apiKey("nafru_...").baseUrl("http://localhost:48787/api").maxRetries(2).build();

var sent = nafru.emails().send(
        new SendEmailInput()
                .from("Acme <hello@example.com>")
                .to("ali@example.org")
                .subject("Welcome")
                .html("<p>Hello!</p>")
                .scheduledAt("in 1 hour"), // optional: ISO 8601 or a relative expression, up to 30 days ahead
        "signup-1042"); // Idempotency-Key: retrying with the same key returns the same email
System.out.println(sent.id());
```

Request objects are built with fluent setters; on the wire fields are `snake_case`, exactly as in the API (`reply_to`,
`scheduled_at`). A setter you never call is not sent; a setter called with `null` sends an explicit `null` (for example
`new UpdateContactInput().firstName(null)` clears the first name). Responses are `record`s (`contact.firstName()`); new fields added by
the server are ignored. The client is thread-safe.

## No real sending in development (dev outbox)

When `NODE_ENV=development`, `emails().send` and `emails().batch` (and `emails().send` on a connection client) do **not** send
anything. Each email is written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the same name,
and the file paths and plain text are printed to the console. The response comes back with a `dev_…` id. Change the folder with
`.devOutbox("tmp/mail")`, or turn it off with `.devOutbox(false)`.

## Errors

Every failed call throws `NafruException` (unchecked):

```java
try {
    nafru.emails().send(input);
} catch (NafruException e) {
    e.getStatusCode(); // Integer; null on network errors and timeouts
    e.getName();       // validation_error, not_found, rate_limit_exceeded, application_error, timeout_error, …
    e.getMessage();
    e.getErrors();     // field details on 422 (List<FieldError>), otherwise empty
    e.getRetryAfter(); // seconds to wait on 429 (Double), otherwise null
}
```

## Retries, timeouts and idempotency

- `429` is retried for every method, honoring `retry-after` (the request was rejected before it was processed).
- `5xx` responses and network errors are retried for `GET`/`DELETE`.
- `POST`/`PATCH` are **not** retried on server errors, because the email could go out twice. Pass an `idempotencyKey` and they are.
- Defaults: 2 retries (`.maxRetries(…)`) and a 30 s timeout (`.timeout(Duration…)`). Backoff starts at 300 ms and grows
  exponentially, up to 8 s.
- Pass `.transport(Transport)` to plug in your own HTTP client or for tests.

## Resources

| Resource              | Methods                                                                                                            |
| --------------------- | ------------------------------------------------------------------------------------------------------------------ |
| `emails()`            | `send` `batch` `get` `list` `update` `cancel`                                                                      |
| `domains()`           | `create` `get` `list` `update` `remove` `verify`                                                                   |
| `contacts()`          | `create` `get` `list` `update` `remove`, `segments().{list,add,remove}`, `topics().{list,update}` (by id or email) |
| `contactProperties()` | `create` `get` `list` `update` `remove`                                                                            |
| `segments()`          | `create` `get` `list` `remove` `contacts`                                                                          |
| `topics()`            | `create` `get` `list` `update` `remove`                                                                            |
| `broadcasts()`        | `create` `get` `list` `update` `remove` `send` `cancel`                                                            |
| `templates()`         | `create` `get` `list` `update` `remove` `publish` `duplicate` `putTranslation` `removeTranslation`                 |
| `brand()`             | `get` `update`: workspace brand (logo, colors, font, footer)                                                       |
| `webhooks()`          | `create` `get` `list` `update` `remove`                                                                            |
| `apiKeys()`           | `create` `list` `remove`                                                                                           |
| `events()`            | `send` `batch` `list`: custom events that trigger automations                                                      |

## Pagination

Lists are cursor-based (`limit`, `after`, `before`). To walk every page (the iterator throws `NafruException` if a page fails):

```java
import com.nafru.email.Pagination;
import com.nafru.email.model.ListContactsQuery;

for (var contact : Pagination.paginate(nafru.contacts()::list, new ListContactsQuery().limit(100))) {
    System.out.println(contact.email());
}
```

## Templates and brand

```java
nafru.templates().create(new CreateTemplateInput("Welcome", "<html><body><p>Hello {{{NAME|friend}}}</p></body></html>")
        .alias("welcome")
        .subject("Welcome {{{NAME|friend}}}")
        .brand(TemplateBrand.of("inherit")));
nafru.templates().publish("welcome");

nafru.emails().send(new SendEmailInput()
        .from("Acme <hello@acme.example>")
        .to("ali@example.org")
        .template("welcome", Map.of("NAME", "Ali")));
```

`brand().update` replaces the **whole** brand; fields you don't send become "not set", so read it with `brand().get()` first and
modify that.

## Recurring broadcasts and data sources

```java
nafru.broadcasts().create(new CreateBroadcastInput("seg_1", "Acme <news@example.com>")
        .templateId("weekly-digest")
        .recurrence(new BroadcastRecurrence.Weekly(List.of(1), "09:00")) // Mondays at 09:00, workspace time zone
        .dataSource(BroadcastDataSourceInput.url("https://example.com/digest.json").headerName("X-Key").headerValue("…")));
```

`recurrence` is `Weekly`, `Monthly` or `Interval`; the `{{{data.*}}}` variables come from `data(Map)` or `dataSource(...)`
(`manual()`, `url(...)`, `webhook()`). On update, `recurrence(null)` / `data(null)` / `dataSource(null)` clears the field. Responses
expose `Broadcast.recurrence()`, `triggerState()`, `nextRunAt()`, `parentId()`, `data()` and `dataSource()`; a recurrence type the
SDK does not know yet is read as `Unknown`.

## Custom events

```java
nafru.events().send(new SendEventInput("plan_upgraded")
        .contactEmail("ali@example.org") // the contact is created if it does not exist
        .properties(Map.of("plan", "pro", "seats", 3)));
```

The `email.`, `contact.`, `segment.`, `topic.` and `automation.` prefixes are reserved for system events.

## Verifying webhook signatures

Webhooks are signed in the Svix / Standard Webhooks format. Use the **raw** request body; JSON that has been parsed and re-encoded
will not match the signature.

```java
import com.nafru.email.WebhookVerifier;

boolean ok = WebhookVerifier.verify(
        rawBody,
        request.getHeader("svix-id"),
        request.getHeader("svix-timestamp"),
        request.getHeader("svix-signature"),
        System.getenv("NAFRU_WEBHOOK_SECRET")); // the signingSecret from the webhooks().create response
if (!ok) { /* respond with 400 */ }
```

Timestamps more than 5 minutes in the past or future are rejected (an overload takes a custom tolerance). During key rotation several
signatures may be sent; one valid signature is enough. A secret that doesn't start with `whsec_` or can't be decoded throws
`IllegalArgumentException`.

## Connect with Nafru (for apps)

If you want your own customers to send from **their own** Nafru Email account, don't ask them to paste an API key. Register your app
in Nafru Email (Developer → Apps) and use `NafruConnect`, which implements an OAuth flow with PKCE.

```java
import com.nafru.email.NafruConnect;
import com.nafru.email.NafruConnection;
import com.nafru.email.model.*;

NafruConnect connect = NafruConnect.builder()
        .clientId(System.getenv("NAFRU_CLIENT_ID"))
        .clientSecret(System.getenv("NAFRU_CLIENT_SECRET")) // server side only
        // .baseUrl("http://localhost:48787/api"): optional, defaults to NafruEmail.DEFAULT_BASE_URL
        // .webUrl(...): the consent screen; defaults to baseUrl with the trailing /api removed (https://email.nafru.com)
        .build();

// 1) Redirect the customer. Store codeVerifier and state in the session.
AuthorizeUrl auth = connect.authorizeUrl(new AuthorizeUrlInput(
        "https://myapp.example/nafru/callback",
        state,
        List.of(AppScope.EMAILS_SEND, AppScope.TEMPLATES_READ, AppScope.SENDERS_READ, AppScope.CONNECTION_READ)));

// 2) On the callback, check state and exchange the code for a connection.
ConnectionGrant grant = connect.exchange(new ExchangeInput(code, codeVerifier, redirectUri));
// Map grant.connectionId() to the customer; store grant.refreshToken() ENCRYPTED.

// 3) Call the API on the customer's behalf. The access token refreshes automatically; the refresh token CHANGES on every refresh.
NafruConnection connection = connect.connection(connectionId, load(connectionId),
        tokens -> save(connectionId, tokens.refreshToken())); // the old token is invalid until this is persisted

ConnectionStatus status = connection.status(); // ready, missing: [domain, sender, …], setupUrl
connection.senders().list();
connection.templates().list(); // the customer's templates + your app's bundle
connection.emails().send(new SendEmailInput().from(from).to(to).subject("…").template("welcome", Map.of()));
```

- If the customer disconnected your app or the refresh token is invalid, `NafruException.getName()` is `connection_revoked`; ask the
  customer to connect again.
- Concurrent calls on the same connection object share a single refresh. If several processes use the same connection, keep the
  refresh token in a shared, consistent store and serialize refreshes with a lock: reusing an old refresh token revokes the
  connection for security.
- If `onTokenRefresh` throws, the call fails with `token_persist_failed`; the new token stays in memory and the next call retries
  saving it.
- Management endpoints (API keys, domains, contacts, broadcasts) cannot be called with a connection token; only sending, reading and
  discovery are available.
- When the customer closes their account in your app, call `connect.revoke(refreshToken)`.

## Deprecation warnings

If the server has deprecated this SDK version (`Deprecation` response header), the client writes a warning to stderr once per
client. The call itself is not affected. Deprecated versions and their sunset dates are listed in
[deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Never embed your API key or `clientSecret` in client applications (Android, desktop). Even a
  `sending_access` key can send email.
- **HTTPS is enforced.** `baseUrl` and `webUrl` must use `https`; plain `http` is accepted only for `localhost`, `*.localhost`,
  `127.0.0.0/8` and `[::1]` (local development). Certificate verification is never disabled.
- **Redirects are refused.** The API never redirects; a 3xx response fails with `unexpected_redirect` instead of forwarding your
  `Authorization` header elsewhere. If you pass your own `HttpClient`, it must use `HttpClient.Redirect.NEVER`.
- **Inputs are checked before sending.** Empty, `.` and `..` path segments and idempotency keys with control characters (CR/LF)
  are rejected with `invalid_argument`. Responses larger than 10 MB fail with `response_too_large`.
- **Secrets are redacted.** `toString()` of the clients, `ConnectionGrant`, `CreatedApiKey`, `Webhook` and transport requests prints
  `[REDACTED]` instead of keys, tokens and secrets; exceptions never contain them.
- **Webhooks:** verify the **raw** request body (bytes as received, decoded as UTF-8), not re-serialized JSON. Signatures are
  compared in constant time, timestamps outside ±5 minutes are rejected, and at most 32 signatures are checked.
- **Reporting vulnerabilities:** do not open a public issue. Use [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new)
  or email security@nafru.com; see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

```sh
./gradlew test                 # unit tests
./gradlew publishToMavenLocal  # unsigned install into ~/.m2
```

The version lives in both `gradle.properties` (`version`) and `src/main/java/com/nafru/email/NafruEmail.java` (`SDK_VERSION`); change them
together.

Publishing to Maven Central (Central Portal) requires the `com.nafru` namespace to be verified on the Portal. With a Portal user token
and an ASCII-armored PGP key:

```sh
export CENTRAL_USERNAME=… CENTRAL_PASSWORD=…        # central.sonatype.com → Generate User Token
export SIGNING_KEY="$(gpg --armor --export-secret-keys KEYID)" SIGNING_PASSWORD=…
./gradlew publishMavenPublicationToCentralRepository
# Transfer the staging repository to the Portal (then click "Publish" there):
curl -X POST -H "Authorization: Bearer $(printf '%s:%s' "$CENTRAL_USERNAME" "$CENTRAL_PASSWORD" | base64)" \
  "https://ossrh-staging-api.central.sonatype.com/manual/upload/defaultRepository/com.nafru?publishing_type=automatic"
```

## Troubleshooting

Every failure is a `NafruException`; `getName()` tells you what went wrong.

- **`invalid_api_key` / `unauthorized` (401):** the key is wrong, revoked or missing. `new NafruEmail()` reads `NAFRU_API_KEY`;
  if that variable is not set in the process environment, construction fails with "apiKey gerekli" (apiKey required).
- **`forbidden` (403):** the key lacks the permission. A `sending_access` key can send email but cannot list or manage
  resources; use a `full_access` key for those calls.
- **`validation_error` (422):** the request body was rejected. `getErrors()` lists each `field` and `message`.
- **`rate_limit_exceeded` (429):** already retried automatically (`maxRetries`, default 2) honoring `retry-after`; if it still
  fails, `getRetryAfter()` says how many seconds to wait.
- **`timeout_error` / `application_error` with `getStatusCode() == null`:** a network failure or timeout (default 30 s, see
  `.timeout(...)`). `GET`/`DELETE` are retried; `POST`/`PATCH` are retried only with an idempotency key, so pass one
  (`emails().send(input, "order-1042")`) to retry a send safely without sending twice.
- **`unexpected_redirect` (3xx):** the API never redirects, so the base URL is wrong (e.g. missing `/api`, `http` → `https`
  redirect) or a proxy is in the way. Fix `baseUrl`; redirects are never followed.
- **"baseUrl https kullanmalı (http yalnız localhost için)"** (`IllegalArgumentException`, "baseUrl must use https"): `baseUrl` /
  `webUrl` must be `https`; plain `http` works only for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **`response_too_large`:** the response body exceeded 10 MB, usually a misconfigured proxy returning something other than
  the API.
- **`invalid_argument`:** an empty, `.` or `..` id/path segment, or an idempotency key that is empty or contains control
  characters; nothing was sent.
- **`connection_revoked` (Connect):** the customer disconnected your app or the refresh token is no longer valid; ask them to
  connect again.
- **`token_persist_failed` (Connect):** your `onTokenRefresh` callback threw. The new refresh token is kept in memory and saving
  is retried on the next call; fix storage before the process restarts, or the connection is lost.
- **Webhook verification returns `false`:** pass the **raw** body exactly as received (not re-serialized JSON), the
  `svix-id`, `svix-timestamp` and `svix-signature` headers, and the webhook's own `whsec_…` signing secret. Check the server
  clock: timestamps more than 5 minutes off are rejected.
- **Emails are not being sent:** with `NODE_ENV=development` the dev outbox is on and emails are written to `.nafru/emails/`
  instead. Use `.devOutbox(false)` in the builder to really send.

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

- Questions and how-tos: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions)
- Bugs in this SDK: [GitHub Issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never a public issue)

See [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md) for details and [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md)
to contribute.

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/java/LICENSE).
