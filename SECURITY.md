# Security Policy

We take the security of the Nafru Email SDKs and the Nafru Email API seriously. Thank you for helping keep our users safe.

## Reporting a vulnerability

**Please do not open a public issue, discussion or pull request for security problems.**

1. Preferred: [report it privately on GitHub](https://github.com/nafrucom/nafru-email-sdks/security/advisories/new)
   (Security → Report a vulnerability).
2. Or email **security@nafru.com**.

Please include the affected SDK and version, a description of the issue and its impact, and steps or code to reproduce
it. If you have a suggested fix, include it too.

### What to expect

| Step                                        | Target time                                  |
| ------------------------------------------- | -------------------------------------------- |
| Acknowledgement of your report              | within 2 business days                       |
| Initial assessment and severity             | within 5 business days                       |
| Fix for critical / high severity            | as fast as possible, normally within 30 days |
| Public advisory and credit (if you want it) | once a fixed version is released             |

We follow coordinated disclosure: please give us a reasonable time to fix the issue before publishing details. We will
keep you informed throughout and will not take legal action against good-faith research that respects this policy
(no access to other users' data, no service disruption, no social engineering).

## Supported versions

All SDKs share one version number and are released together.

| Version              | Security fixes                                                                                                                                              |
| -------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------- |
| Latest minor release | Yes                                                                                                                                                         |
| Older releases       | No; please upgrade. Deprecated versions are listed in [`deprecations.json`](deprecations.json) and receive a `Deprecation` / `Sunset` warning from the API. |

## How the SDKs protect you

- **API keys stay on your server.** Never ship a key to a browser, mobile app or public repository; any key can send
  email. Load it from an environment variable (`NAFRU_API_KEY`) or a secret manager.
- **HTTPS only.** A base URL that is not `https` is rejected (plain `http` is accepted only for `localhost`).
- **Redirects are refused.** The API never redirects; following one could send your `Authorization` header to another
  host, so the SDKs return an `unexpected_redirect` error instead.
- **Certificate verification is always on.** There is no option to turn it off.
- **Input checks.** Empty, `.` and `..` path parameters and idempotency keys with control characters are rejected before
  any request is sent.
- **Secrets are redacted** from the default string / debug / log output of clients, options and OAuth grants.
- **Response size is capped** at 10 MB.
- **Webhook signatures** are verified with HMAC-SHA256, constant-time comparison and a 5-minute timestamp tolerance.
  Always verify the _raw_ request body.
- **Minimal dependencies.** Most SDKs use only the standard library; dependencies are monitored with Dependabot and
  CodeQL scans this repository.

If you suspect a key has leaked, revoke it immediately in the Nafru Email dashboard and create a new one.
