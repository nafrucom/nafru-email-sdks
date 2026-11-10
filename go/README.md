# Nafru Email Go SDK

The official **Nafru Email Go SDK** for the Nafru Email API, a transactional and marketing **email API**. Use it to **send email from Go**,
manage domains, contacts, templates and broadcasts, and verify **webhooks**. The API is **Resend-compatible**, so request shapes, field
names and errors match Resend. The SDK uses only the standard library, and every call takes a `context.Context`.

[![Go Reference](https://pkg.go.dev/badge/github.com/nafrucom/nafru-email-sdks/go.svg)](https://pkg.go.dev/github.com/nafrucom/nafru-email-sdks/go)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/go/LICENSE)

## Requirements

Go 1.21 or later.

## Installation

```sh
go get github.com/nafrucom/nafru-email-sdks/go
```

```go
import nafruemail "github.com/nafrucom/nafru-email-sdks/go"
```

## Quick start: send an email

```go
client, err := nafruemail.NewClient("nafru_...") // or nafruemail.NewClient("") to read NAFRU_API_KEY from the environment
// The base URL is optional and defaults to nafruemail.DefaultBaseURL (https://email.nafru.com/api).
// For local development: nafruemail.NewClient("", nafruemail.WithBaseURL("http://localhost:48787/api"))
if err != nil {
	log.Fatal(err)
}

sent, err := client.Emails.Send(ctx, &nafruemail.SendEmailInput{
	From:        "Acme <hello@example.com>",
	To:          []string{"jane@example.org"},
	Subject:     "Welcome",
	HTML:        "<p>Hello!</p>",
	ScheduledAt: "in 1 hour", // optional: ISO 8601 or a relative expression, up to 30 days ahead
}, nafruemail.SendEmailOptions{IdempotencyKey: "signup-1042"}) // retrying with the same key returns the same email
if err != nil {
	log.Fatal(err)
}
fmt.Println(sent.ID)
```

Field names on the wire are `snake_case` exactly as in the API (`reply_to`, `scheduled_at`, `first_name`); the Go fields map to them.
Optional bool/number fields are pointers: `nafruemail.Ptr(true)`. In updates, use `nafruemail.Null[string]()` to **clear** a field (JSON `null`) and
`nafruemail.Value("x")` to set it; a `nil` field is not sent at all.

```go
client.Contacts.Update(ctx, "jane@example.org", &nafruemail.UpdateContactInput{
	FirstName:    nafruemail.Value("Jane"),
	LastName:     nafruemail.Null[string](), // clear the last name
	Unsubscribed: nafruemail.Ptr(false),
})
```

## No sending in development

When `NODE_ENV=development`, `Emails.Send` and `Emails.Batch` (and `Emails.Send` on a connection client) **do not send** anything. Each email is
written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the same name, and the file paths and plain
text are printed to the console. The call returns a `dev_…` id. Change the folder with `nafruemail.WithDevOutbox("tmp/mail")`, or turn this off with
`nafruemail.WithoutDevOutbox()`.

## Errors

Every failed call returns a `*nafruemail.Error`:

```go
type Error struct {
	StatusCode int          // 0 on network errors and timeouts
	Name       string       // validation_error, not_found, rate_limit_exceeded, timeout_error, application_error, …
	Message    string
	Errors     []FieldError // per-field details on 422
	RetryAfter *float64     // seconds, on 429
}
```

```go
var apiErr *nafruemail.Error
if errors.As(err, &apiErr) && apiErr.Name == "not_found" {
	// …
}
```

## Retries, timeouts and idempotency

- `429` is retried on every method, honoring `retry-after` (the request was rejected before being processed).
- `GET`/`DELETE` are retried on `5xx` and network errors (300 ms × 2ⁿ, at most 8 s).
- `POST`/`PATCH`/`PUT` are **not** retried on server errors, because an email could go out twice; they are retried if you pass `IdempotencyKey`.
- Defaults: 2 retries (`nafruemail.WithMaxRetries(n)`; `0` disables) and a 30 s timeout per attempt (`nafruemail.WithTimeout(d)`).
- You can pass a custom `*http.Client` with `nafruemail.WithHTTPClient` (proxy, tests).

## Resources

|                     |                                                                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
| `Emails`            | `Send` `Batch` `Get` `List` `Update` `Cancel`                                                                                     |
| `Domains`           | `Create` `Get` `List` `Update` `Remove` `Verify`                                                                                  |
| `Contacts`          | `Create` `Get` `List` `Update` `Remove`, `Segments.{List,Add,Remove}`, `Topics.{List,Update}` (accepts an id or an email address) |
| `ContactProperties` | `Create` `Get` `List` `Update` `Remove`                                                                                           |
| `Segments`          | `Create` `Get` `List` `Remove` `Contacts`                                                                                         |
| `Topics`            | `Create` `Get` `List` `Update` `Remove`                                                                                           |
| `Broadcasts`        | `Create` `Get` `List` `Update` `Remove` `Send` `Cancel`                                                                           |
| `Templates`         | `Create` `Get` `List` `Update` `Remove` `Publish` `Duplicate` `PutTranslation` `RemoveTranslation` (id or alias)                  |
| `Brand`             | `Get` `Update`: workspace branding (logo, colors, font, footer)                                                                   |
| `Webhooks`          | `Create` `Get` `List` `Update` `Remove`                                                                                           |
| `APIKeys`           | `Create` `List` `Remove`                                                                                                          |
| `Events`            | `Send` `Batch` `List`: custom events that trigger automations                                                                     |

## Pagination

Lists are cursor-based (`Limit`, `After`, `Before`). To walk every page:

```go
pager := nafruemail.Paginate(ctx, func(ctx context.Context, after string) (*nafruemail.ListResponse[nafruemail.Contact], error) {
	return client.Contacts.List(ctx, &nafruemail.ListContactsQuery{ListQuery: nafruemail.ListQuery{Limit: 100, After: after}})
})
for pager.Next() {
	fmt.Println(pager.Item().Email)
}
if err := pager.Err(); err != nil { // an error stops iteration; you never silently read partial data
	log.Fatal(err)
}
```

## Templates and branding

```go
client.Templates.Create(ctx, &nafruemail.CreateTemplateInput{
	Name:    "Welcome",
	Alias:   "welcome",
	Subject: "Welcome {{{NAME|friend}}}",
	HTML:    "<html><body><p>Hello {{{NAME|friend}}}</p></body></html>",
	Brand:   &nafruemail.TemplateBrand{Mode: "inherit"}, // inherit the workspace brand
})
client.Templates.Publish(ctx, "welcome")

client.Emails.Send(ctx, &nafruemail.SendEmailInput{
	From:     "Acme <hello@acme.example>",
	To:       []string{"jane@example.org"},
	Template: &nafruemail.EmailTemplate{ID: "welcome", Variables: map[string]any{"NAME": "Jane"}},
})
```

`Brand.Update` replaces the **whole** brand; any field you leave out becomes "not set", so read it with `Brand.Get` first and modify that.
A template's `Brand.Mode`: `inherit` (from the brand), `custom` (with `Override`), `none` (nothing is added; the default for templates
created through the API).

## Recurring broadcasts and data sources

A broadcast with `Recurrence` is a recurring template: `Send` activates it, and each run creates a new broadcast. `{{{data.*}}}` variables in
the template are filled from `Data` or `DataSource` (`manual`, `url`, `webhook`).

```go
client.Broadcasts.Create(ctx, &nafruemail.CreateBroadcastInput{
	SegmentID:  "seg_…",
	From:       "Acme <news@acme.example>",
	TemplateID: "weekly-digest",
	Recurrence: &nafruemail.BroadcastRecurrence{Type: nafruemail.RecurrenceWeekly, Days: []int{1}, Time: "09:00"}, // Mondays at 09:00
	DataSource: &nafruemail.BroadcastDataSourceInput{Type: nafruemail.DataSourceURL, URL: "https://acme.example/digest.json"},
})

// Send null to remove the recurrence.
client.Broadcasts.Update(ctx, "bc_…", &nafruemail.UpdateBroadcastInput{Recurrence: nafruemail.Null[nafruemail.BroadcastRecurrence]()})
```

Union types (`BroadcastRecurrence`, `BroadcastDataSource`) are flat structs discriminated by their `Type` field; only the fields for that type
are populated, and an unknown type decodes without an error.

## Custom events

```go
client.Events.Send(ctx, &nafruemail.SendEventInput{
	Name:       "plan_upgraded",
	Contact:    nafruemail.EventContact{Email: "jane@example.org"}, // created if it does not exist
	Properties: map[string]any{"plan": "pro", "seats": 3},
})
```

## Verifying webhook signatures

The server signs webhooks in the Svix/Standard Webhooks format. Use the **raw** body; parsed and re-serialized JSON breaks the signature.

```go
func handler(w http.ResponseWriter, r *http.Request) {
	payload, _ := io.ReadAll(r.Body)
	valid, err := nafruemail.VerifyWebhook(nafruemail.VerifyWebhookInput{
		Payload: string(payload),
		Headers: nafruemail.WebhookHeaders{
			ID:        r.Header.Get("svix-id"),
			Timestamp: r.Header.Get("svix-timestamp"),
			Signature: r.Header.Get("svix-signature"),
		},
		Secret: os.Getenv("NAFRU_WEBHOOK_SECRET"), // SigningSecret from the Webhooks.Create response
	})
	if err != nil || !valid {
		http.Error(w, "invalid signature", http.StatusBadRequest)
		return
	}
	var event nafruemail.WebhookPayload
	json.Unmarshal(payload, &event)
}
```

Timestamps more than 5 minutes in the past or future are rejected (`ToleranceSeconds`). During key rotation several signatures may be sent;
one valid signature is enough. A malformed `Secret` returns an error (a configuration error); a malformed signature or timestamp returns `false`.

## Connect with Nafru (for apps)

If you want your own product's customers to send from **their own** Nafru Email account, do not ask them to copy an API key: register your app
in Nafru Email (Developer → Apps) and use `nafruemail.NewConnect`.

```go
connect, err := nafruemail.NewConnect(nafruemail.ConnectOptions{
	ClientID:     os.Getenv("NAFRU_CLIENT_ID"),
	ClientSecret: os.Getenv("NAFRU_CLIENT_SECRET"), // server-side only
	// BaseURL is optional (defaults to nafruemail.DefaultBaseURL; locally http://localhost:48787/api).
	// WebURL: the consent screen; if empty, the trailing /api is stripped from BaseURL
})

// 1) Redirect the customer. Store CodeVerifier and state in the session.
auth, err := connect.AuthorizeURL(nafruemail.AuthorizeURLInput{
	RedirectURI: "https://myapp.example/nafru/callback",
	State:       state,
	Scopes:      []string{nafruemail.ScopeEmailsSend, nafruemail.ScopeTemplatesRead, nafruemail.ScopeSendersRead, nafruemail.ScopeConnectionRead},
})
http.Redirect(w, r, auth.URL, http.StatusFound)

// 2) On return, verify state and exchange the code for a connection.
grant, err := connect.Exchange(ctx, nafruemail.ExchangeInput{Code: code, CodeVerifier: verifier, RedirectURI: redirectURI})
// Map grant.ConnectionID to the customer; store grant.RefreshToken ENCRYPTED.

// 3) Call on the customer's behalf. The access token is refreshed automatically; the refresh token CHANGES on every refresh.
connection := connect.Connection(connectionID, nafruemail.ConnectionOptions{
	RefreshToken: load(connectionID),
	OnTokenRefresh: func(ctx context.Context, tokens nafruemail.ConnectionTokens) error {
		return save(ctx, connectionID, tokens.RefreshToken) // the old token is invalid once rotated, so persist it
	},
})

status, err := connection.Status(ctx) // Ready, Missing: [domain sender …], SetupURL
connection.Senders.List(ctx)
connection.Templates.List(ctx) // the customer's templates + your app's bundle
connection.Emails.Send(ctx, &nafruemail.SendEmailInput{From: from, To: to, Subject: subject,
	Template: &nafruemail.EmailTemplate{ID: "welcome"}})
```

- If the customer disconnected or the refresh token is invalid, `Name == "connection_revoked"`; ask the customer to reconnect.
- Share a single `*Connection` per connection: concurrent calls share a single refresh (single flight). If several processes use the same
  connection, keep the refresh token in a shared, consistent store and serialize refreshes with a lock: reusing an old token revokes the
  connection for security.
- If `OnTokenRefresh` returns an error, the call returns `token_persist_failed`; the new token stays in memory and saving is retried on the
  next call.
- On `401 invalid_token` the token is refreshed once and the request is retried.
- Management endpoints (keys, domains, contacts, broadcasts) cannot be called with a connection token; only sending, reading and discovery are
  available.
- When the customer closes their account: `connect.Revoke(ctx, refreshToken)`.

## Deprecation warnings

When the API deprecates this SDK version, responses carry a `Deprecation` header; a warning is printed to stderr once per client (with the
sunset date and a details link when present). The call itself is not affected. Supported and deprecated versions are listed in
[deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- **Keep keys server-side.** Never embed the API key or the Connect client secret in a browser, mobile or desktop app. Even a
  `sending_access` key can send email.
- **HTTPS is enforced.** `NewClient` and `NewConnect` reject a base URL or web URL that is not `https`; plain `http` is accepted only for
  `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **Redirects are refused.** The API never redirects, so the client does not follow one (that could leak the `Authorization` header to
  another host). A `3xx` response returns an `unexpected_redirect` error and is never retried. This also applies to an `*http.Client` you
  pass with `WithHTTPClient`.
- **Inputs are checked before sending.** Empty, `.` or `..` path parameters and idempotency keys containing control characters (CR, LF, …)
  return an `invalid_argument` error. Response bodies are capped at 10 MB (`response_too_large`).
- **Secrets are redacted.** Types that hold a secret (the Connect client, `ConnectOptions`, `ConnectionOptions`, `ConnectionGrant`,
  `ConnectionTokens`, `CreatedAPIKey`, webhook secrets, …) print `[REDACTED]` in every `fmt` verb (`%v`, `%+v`, `%#v`, …). Errors never
  contain keys or tokens.
- **Verify webhooks on the raw body.** Pass the exact request bytes to `VerifyWebhook`; signatures are compared in constant time, the
  timestamp must be within 5 minutes in either direction, and only the first 32 signatures in the header are considered.
- PKCE verifiers and dev ids come from `crypto/rand`; TLS certificate verification is never disabled.
- **Reporting a vulnerability:** do not open a public issue. Use
  [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email
  security@nafru.com. See [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

```sh
go test -race ./...
go vet ./...
```

## Troubleshooting

Every API failure is a `*nafruemail.Error`; check `Name` (use `errors.As`). Constructor errors are returned by `NewClient` / `NewConnect`.

- **`apiKey gerekli` from `NewClient`:** no key was passed and `NAFRU_API_KEY` is not set (or is empty) in the process environment.
- **`missing_api_key` / `unauthorized` (401) / `invalid_api_key` (403):** the key is wrong, deleted or revoked, or belongs to another
  environment (for example a staging key against production). Create a new key in the dashboard.
- **`restricted_api_key` / `forbidden` (403):** the key lacks the permission. A `sending_access` key can only send email; listing or
  managing resources needs a `full_access` key. A domain-restricted key can only send from its domain. On a Connect connection,
  `insufficient_scope` means the customer did not grant that scope.
- **`validation_error` (422):** the request body is invalid. `Errors` lists each problem as `Field` + `Message`.
- **`rate_limit_exceeded` (429):** already retried automatically (`WithMaxRetries`, default 2) honoring `retry-after`. If it still
  fails, `RetryAfter` holds the seconds to wait; slow down or use `Emails.Batch`.
- **`timeout_error` / `application_error` with `StatusCode == 0`:** a network failure or the per-attempt timeout (`WithTimeout`,
  default 30 s). `GET`/`DELETE` are retried; `POST`/`PATCH` are retried only with an idempotency key, so pass
  `SendEmailOptions{IdempotencyKey: …}` when you send, then retrying yourself cannot send twice.
- **`unexpected_redirect` (3xx):** the base URL is wrong (for example missing `/api`, or pointing at the dashboard) or a proxy is
  redirecting. Point `WithBaseURL` at the API root, for example `https://email.nafru.com/api`.
- **`invalid_argument` "baseUrl https kullanmalı (http yalnız localhost için)":** the base URL (or Connect `WebURL`) uses `http`
  on a non-local host. Use `https`; plain `http` is accepted only for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.
- **`invalid_argument` on a call:** a path parameter (id, email, alias, locale) is empty, `.` or `..`, or an idempotency key
  contains a control character. No request was sent.
- **`response_too_large`:** the response exceeded 10 MB, usually a misbehaving proxy returning something other than the API.
- **`connection_revoked` (Connect):** the customer disconnected your app or the refresh token is invalid or already used. Ask the
  customer to connect again; share one `*Connection` per connection so concurrent calls do not reuse an old refresh token.
- **`token_persist_failed` (Connect):** your `OnTokenRefresh` returned an error. The new refresh token is kept in memory and saving is
  retried on the next call; fix your storage before the process restarts, or the connection is lost.
- **`VerifyWebhook` returns `false`:** pass the **raw** request body (not re-serialized JSON), use the endpoint's own `whsec_…`
  secret, pass the `svix-id`, `svix-timestamp` and `svix-signature` headers unchanged, and check the server clock (more than
  5 minutes of skew is rejected). It returns an error only when the secret itself is malformed.
- **Emails are not being sent, ids start with `dev_`:** `NODE_ENV=development` turns on the dev outbox; emails are written to
  `.nafru/emails/` instead. Unset `NODE_ENV` or pass `nafruemail.WithoutDevOutbox()` (`DisableDevOutbox: true` for Connect).

## Support

- Questions and how-tos: [GitHub Discussions](https://github.com/nafrucom/nafru-email-sdks/discussions).
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues).
- Account, billing and deliverability: destek@nafru.com.
- Security issues: [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never a public issue).

More in [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md). To contribute, see
[CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md).

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

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/go/LICENSE).
