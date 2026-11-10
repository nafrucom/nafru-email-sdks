# Nafru Email PHP SDK

The official **Nafru Email PHP SDK** is the easiest way to send email from PHP with the Nafru Email API. Use it to send
transactional email (sign-up confirmations, password resets, receipts) and marketing broadcasts, manage contacts, templates and
domains, trigger automations with custom events, and verify webhooks. The email API is Resend-compatible, so the request and
response shapes will feel familiar if you are coming from Resend.

[![Packagist Version](https://img.shields.io/packagist/v/nafrucom/email)](https://packagist.org/packages/nafrucom/email)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](https://github.com/nafrucom/nafru-email-sdks/blob/main/php/LICENSE)

## Requirements

- PHP 8.1 or later
- `ext-curl` and `ext-json`. There are no other dependencies.

## Installation

```sh
composer require nafrucom/email
```

## Quick start: send an email

```php
use Nafru\Email\NafruEmail;
use Nafru\Email\NafruException;

$nafru = new NafruEmail('nafru_123'); // or `new NafruEmail()` to read the NAFRU_API_KEY environment variable

try {
    $email = $nafru->emails->send(
        [
            'from' => 'Acme <hello@example.com>',
            'to' => 'ali@example.org',
            'subject' => 'Welcome',
            'html' => '<p>Hello!</p>',
            'scheduled_at' => 'in 1 hour', // optional: ISO 8601 or a relative expression, up to 30 days ahead
        ],
        idempotencyKey: 'signup-1042', // retrying with the same key returns the same email
    );
    echo $email['id'];
} catch (NafruException $e) {
    error_log("{$e->statusCode} {$e->name} {$e->getMessage()}");
}
```

Body fields are `snake_case`, exactly as in the API (`reply_to`, `scheduled_at`, `first_name`). There is no conversion layer, so what
you write matches the docs and the wire format one to one. Requests and responses are plain arrays; their shapes are declared as
PHPStan/Psalm types in `Nafru\Email\Types`, so your IDE and static analysis know the fields.

Where the API expects an empty object (maps such as `properties` or `variables`), an empty PHP array is encoded as `[]` in JSON;
pass `new stdClass()` instead.

All other settings are optional named arguments:

```php
$nafru = new NafruEmail(
    'nafru_123',
    baseUrl: 'http://localhost:48787/api', // default NafruEmail::DEFAULT_BASE_URL (https://email.nafru.com/api)
    maxRetries: 3,
    timeout: 10.0,
);
```

Client options: `baseUrl`, `transport` (your own `Nafru\Email\Http\Transport` implementation for tests, proxies or Guzzle), `maxRetries`
(default 2), `timeout` (seconds, default 30) and `devOutbox`.

## No real sending in development (dev outbox)

When `NODE_ENV=development`, `emails->send` and `emails->batch` (and `emails->send` on a connection client) do **not** send
anything. Each email is written under `.nafru/emails/` as plain text (`.txt`, headers + body) plus an `.html` file with the same name,
and the file paths and plain text are logged with `error_log` (stderr on the CLI; it never leaks into a web response). The response
carries a `dev_…` id. Change the folder with `devOutbox: 'tmp/mail'`, or turn it off with `devOutbox: false`.

## Errors

Every failed call throws `Nafru\Email\NafruException`:

| Field              | Description                                                                                                                                      |
| ------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `$e->statusCode`   | HTTP status; `null` on network errors and timeouts                                                                                               |
| `$e->name`         | `validation_error`, `not_found`, `rate_limit_exceeded`, `template_in_use`, …; `application_error` on network errors, `timeout_error` on timeouts |
| `$e->getMessage()` | Message                                                                                                                                          |
| `$e->errors`       | Field details on 422: `[['field' => 'to', 'message' => '…'], …]`                                                                                 |
| `$e->retryAfter`   | Seconds to wait on 429                                                                                                                           |

A missing API key (no argument and no `NAFRU_API_KEY`), a non-https `baseUrl`/`webUrl` or a malformed webhook secret throws
`InvalidArgumentException` (a configuration error). Client-side checks raise `NafruException` before any request is sent:
`invalid_argument` (an empty, `.` or `..` id, or an `idempotencyKey` that is empty or contains control characters),
`unexpected_redirect` (the server answered with a 3xx; redirects are never followed or retried) and `response_too_large`
(response body over 10 MB).

## Retries, timeouts and idempotency

- `429` is retried for every method, honoring `retry-after` (the request was rejected before it was processed).
- `5xx` responses and network errors are retried for `GET`/`DELETE` (300 ms × 2ⁿ, at most 8 s).
- `POST`/`PATCH` are **not** retried on server errors, because the email could go out twice. Pass an `idempotencyKey` and they are.
- Defaults: 2 retries (`maxRetries`) and a 30 s timeout (`timeout`).

## Resources

| Resource            | Methods                                                                                                             |
| ------------------- | ------------------------------------------------------------------------------------------------------------------- |
| `emails`            | `send` `batch` `get` `list` `update` `cancel`                                                                       |
| `domains`           | `create` `get` `list` `update` `remove` `verify`                                                                    |
| `contacts`          | `create` `get` `list` `update` `remove`, `segments->{list,add,remove}`, `topics->{list,update}` (by id or email)    |
| `contactProperties` | `create` `get` `list` `update` `remove`                                                                             |
| `segments`          | `create` `get` `list` `remove` `contacts`                                                                           |
| `topics`            | `create` `get` `list` `update` `remove`                                                                             |
| `broadcasts`        | `create` `get` `list` `update` `remove` `send` `cancel`                                                             |
| `templates`         | `create` `get` `list` `update` `remove` `publish` `duplicate` `putTranslation` `removeTranslation` (by id or alias) |
| `brand`             | `get` `update`: workspace brand (logo, colors, font, footer); `update` replaces the **whole** brand                 |
| `webhooks`          | `create` `get` `list` `update` `remove`                                                                             |
| `apiKeys`           | `create` `list` `remove`                                                                                            |
| `events`            | `send` `batch` `list`: custom events that trigger automations                                                       |

## Pagination

Lists are cursor-based (`limit`, `after`, `before`). To walk every page:

```php
use Nafru\Email\Pagination;

foreach (Pagination::paginate($nafru->contacts->list(...), ['limit' => 100]) as $contact) {
    echo $contact['email'], PHP_EOL;
}
```

If a page cannot be read, the loop throws `NafruException` instead of silently stopping and handing you partial data.

## Templates

```php
$nafru->templates->create([
    'name' => 'Welcome',
    'alias' => 'welcome',
    'subject' => 'Welcome {{{NAME|friend}}}',
    'html' => '<html><body><p>Hello {{{NAME|friend}}}</p></body></html>',
    'brand' => ['mode' => 'inherit'],
]);
$nafru->templates->publish('welcome');

$nafru->emails->send([
    'from' => 'Acme <hello@acme.example>',
    'to' => 'ali@example.org',
    'template' => ['id' => 'welcome', 'variables' => ['NAME' => 'Ali']],
]);
```

## Recurring broadcasts and data sources

A broadcast with `recurrence` is a blueprint: `send` does not start it, it activates it, and every run creates a new broadcast.
`data` and `data_source` fill the template's `{{{data.*}}}` variables. On update, a `null` field clears it and an omitted field is
left unchanged.

```php
$nafru->broadcasts->create([
    'segment_id' => 'seg_…',
    'from' => 'Acme <hello@acme.example>',
    'template_id' => 'weekly-digest',
    'recurrence' => ['type' => 'weekly', 'days' => [1], 'time' => '09:00'], // or monthly{day}, interval{every_days}
    'data_source' => ['type' => 'url', 'url' => 'https://acme.example/digest.json', 'header_name' => 'X-Key', 'header_value' => '…'],
]);
$nafru->broadcasts->update('bc_…', ['recurrence' => null]); // stop recurring
$nafru->broadcasts->send('bc_…', ['data' => ['coupon' => 'WINTER25']]);
```

## Custom events

```php
$nafru->events->send([
    'name' => 'plan_upgraded',
    'contact' => ['email' => 'ali@example.org'], // the contact is created if it does not exist
    'properties' => ['plan' => 'pro', 'seats' => 3],
]);
```

The `email.`, `contact.`, `segment.`, `topic.` and `automation.` prefixes are reserved for system events.

## Verifying webhook signatures

Webhooks are signed in the Svix / Standard Webhooks format. Use the **raw** request body; JSON that has been parsed and re-encoded
will not match the signature.

```php
use Nafru\Email\Webhook;

$ok = Webhook::verify(
    payload: file_get_contents('php://input'),
    headers: [
        'id' => $_SERVER['HTTP_SVIX_ID'] ?? '',
        'timestamp' => $_SERVER['HTTP_SVIX_TIMESTAMP'] ?? '',
        'signature' => $_SERVER['HTTP_SVIX_SIGNATURE'] ?? '',
    ],
    secret: getenv('NAFRU_WEBHOOK_SECRET'), // the signing_secret from the webhooks->create response
);
if (!$ok) {
    http_response_code(400);
    exit('invalid signature');
}
```

Timestamps more than 5 minutes in the past or future are rejected (`toleranceSeconds`). During key rotation several signatures may
be sent; one valid signature is enough (only the first 32 are checked). Missing or empty headers return `false`.

## Connect with Nafru (for apps)

If you want your own customers to send from **their own** Nafru Email account, don't ask them to paste an API key. Register your app
in Nafru Email (Developer → Apps) and use `NafruConnect`, which implements an OAuth flow with PKCE.

```php
use Nafru\Email\NafruConnect;

$connect = new NafruConnect(
    clientId: getenv('NAFRU_CLIENT_ID'),
    clientSecret: getenv('NAFRU_CLIENT_SECRET'), // server side only
    // baseUrl: optional; defaults to https://email.nafru.com/api ('http://localhost:48787/api' locally)
    // webUrl: the consent screen; defaults to baseUrl with the trailing /api removed
);

// 1) Redirect the customer. Store codeVerifier and state in the session.
$auth = $connect->authorizeUrl(
    redirectUri: 'https://myapp.example/nafru/callback',
    state: $state,
    scopes: ['emails.send', 'templates.read', 'senders.read', 'connection.read'],
);
$_SESSION['nafru_verifier'] = $auth['codeVerifier'];
header('Location: ' . $auth['url']);

// 2) On the callback, check state and exchange the code for a connection.
$grant = $connect->exchange($_GET['code'], $_SESSION['nafru_verifier'], $redirectUri);
// Map $grant->connectionId to the customer; store $grant->refreshToken ENCRYPTED.

// 3) Call the API on the customer's behalf. The access token refreshes automatically; the refresh token CHANGES on every refresh.
$connection = $connect->connection(
    $connectionId,
    refreshToken: load($connectionId),
    onTokenRefresh: fn (array $tokens) => save($connectionId, $tokens['refreshToken']), // the old token is invalid until this is persisted
);

$status = $connection->status(); // ready, missing: ['domain','sender',…], setup_url
$connection->senders();
$connection->templates(); // the customer's templates + your app's bundle
$connection->emails->send(['from' => $from, 'to' => $to, 'subject' => 'S', 'template' => ['id' => 'welcome']]);
```

- If the customer disconnected your app or the refresh token is invalid, `$e->name === 'connection_revoked'`; ask the customer to
  connect again.
- A single `Connection` object refreshes once and reuses the token; on a 401 `invalid_token` it refreshes once and retries. In
  multi-process environments such as PHP-FPM every request builds its own object: keep the refresh token in a shared, consistent
  store and serialize refreshes with a lock (for example a database row lock). Reusing an old refresh token revokes the connection
  for security.
- If `onTokenRefresh` throws, the call fails with `token_persist_failed`; the new token stays in memory and the next call retries
  saving it.
- Management endpoints (API keys, domains, contacts, broadcasts) cannot be called with a connection token; only sending, reading and
  discovery are available.
- When the customer closes their account in your app, call `$connect->revoke($refreshToken)`.

## Deprecation warnings

When the server deprecates this SDK version, responses carry a `Deprecation` header and the client logs a warning once via
`error_log` (with the sunset date and a details link when available). The call itself is not affected. Deprecated versions are
listed in [deprecations.json](https://github.com/nafrucom/nafru-email-sdks/blob/main/deprecations.json).

## Security

- Keep your API key and `clientSecret` on the server. Never ship them to a browser or mobile app; even a `sending_access` key can
  send email.
- HTTPS is enforced: `baseUrl` and `webUrl` must use `https` (plain `http` is accepted only for `localhost`, `*.localhost`,
  `127.0.0.0/8` and `[::1]`). TLS certificate verification is always on and cannot be disabled.
- Redirects are refused (`unexpected_redirect`), so your key or tokens are never forwarded to another host.
- Secrets are redacted: `var_dump`/`print_r` of the clients, a connection or a `ConnectionGrant` show `[REDACTED]`, and secret
  constructor arguments are marked `#[\SensitiveParameter]` so they do not appear in stack traces (PHP 8.2+). `var_export` and
  `serialize` bypass this, so don't log those.
- Verify webhooks against the **raw** request body (`file_get_contents('php://input')`), never re-encoded JSON.
- Please report vulnerabilities privately, never in a public issue: use
  [GitHub private vulnerability reporting](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new) or email
  security@nafru.com. See [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md).

## Development

```sh
composer install
composer test
```

## Troubleshooting

Every API failure is a `NafruException`; check `$e->name` first.

| `$e->name` / symptom                                                    | What it means and what to do                                                                                                                                                                                                   |
| ----------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `unauthorized`, `invalid_api_key` (401)                                 | The key is wrong or revoked, or `new NafruEmail()` found no `NAFRU_API_KEY` in the environment (`getenv`). Create a new key in the dashboard.                                                                                  |
| `forbidden` (403)                                                       | The key lacks permission, e.g. a `sending_access` key can send but cannot list or manage resources. Use a `full_access` key.                                                                                                   |
| `validation_error` (422)                                                | The request body is invalid; `$e->errors` lists each `field` and `message`. Field names are `snake_case`.                                                                                                                      |
| `rate_limit_exceeded` (429)                                             | Retried automatically (`maxRetries`, default 2), honoring `retry-after`. If it still fails, wait `$e->retryAfter` seconds.                                                                                                     |
| `timeout_error`, `application_error` with `statusCode === null`         | Network problem or timeout (`timeout`, default 30 s). `GET`/`DELETE` are retried; `POST`/`PATCH` are retried only with an `idempotencyKey`, so pass one to retry sends safely.                                                 |
| `unexpected_redirect` (3xx)                                             | The SDK never follows redirects. The `baseUrl` is wrong (missing `/api`, `http` → `https` redirect) or a proxy is redirecting.                                                                                                 |
| `InvalidArgumentException`: "baseUrl https kullanmalı" (must use https) | `baseUrl`/`webUrl` must be `https`; `http` is allowed only for `localhost`, `*.localhost`, `127.0.0.0/8` and `[::1]`.                                                                                                          |
| `response_too_large`                                                    | The response body exceeded 10 MB, usually a misconfigured proxy or wrong `baseUrl`.                                                                                                                                            |
| `invalid_argument`                                                      | Rejected before sending: an empty, `.` or `..` id, or an `idempotencyKey` that is empty or has control characters.                                                                                                             |
| `connection_revoked` (Connect)                                          | The customer disconnected your app or the refresh token is invalid or was reused. Ask the customer to connect again.                                                                                                           |
| `token_persist_failed` (Connect)                                        | Your `onTokenRefresh` callback threw. The new refresh token is kept in memory and saving is retried on the next call; fix storage before the process exits.                                                                    |
| `Webhook::verify()` returns `false`                                     | Pass the **raw** body (`file_get_contents('php://input')`), the endpoint's `whsec_…` secret, and all three `svix-id` / `svix-timestamp` / `svix-signature` headers. Check the server clock: more than 5 minutes of skew fails. |
| Emails are not being sent, ids start with `dev_`                        | `NODE_ENV=development` turns on the dev outbox: emails are written to `.nafru/emails/` instead. Pass `devOutbox: false` to send for real.                                                                                      |

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
- Bugs in this SDK: [GitHub issues](https://github.com/nafrucom/nafru-email-sdks/issues)
- Account, billing and deliverability: destek@nafru.com
- Security vulnerabilities: see [SECURITY.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SECURITY.md) (never in a public issue)

More in [SUPPORT.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/SUPPORT.md). Contributions are welcome; see [CONTRIBUTING.md](https://github.com/nafrucom/nafru-email-sdks/blob/main/CONTRIBUTING.md).

## License

MIT. See [LICENSE](https://github.com/nafrucom/nafru-email-sdks/blob/main/php/LICENSE).
