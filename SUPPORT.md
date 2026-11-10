# Getting help

| You want to…                                                   | Go to                                                                                                          |
| -------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------------- |
| Ask how to do something with an SDK                            | [GitHub Discussions → Q&A](https://github.com/nafrucom/nafru-email-sdks/discussions/categories/q-a)            |
| Report a bug in an SDK                                         | [Open a bug report](https://github.com/nafrucom/nafru-email-sdks/issues/new?template=bug_report.yml)           |
| Request a feature or a new language                            | [Open a feature request](https://github.com/nafrucom/nafru-email-sdks/issues/new?template=feature_request.yml) |
| Report a security vulnerability                                | **Privately**, see [SECURITY.md](SECURITY.md) — never in a public issue                                        |
| Get help with your account, billing, domains or deliverability | **destek@nafru.com** or the support link in the Nafru Email dashboard                                          |

## Before you ask

1. Check the README of your SDK: each one has a **Troubleshooting** section for common errors
   (`invalid_api_key`, `restricted_api_key`, `validation_error`, `rate_limit_exceeded`, `unexpected_redirect`, timeouts, webhook verification).
2. Make sure you run the [latest version](https://github.com/nafrucom/nafru-email-sdks/releases). If your version is
   listed in [`deprecations.json`](deprecations.json), upgrade first.
3. Search [existing issues](https://github.com/nafrucom/nafru-email-sdks/issues?q=is%3Aissue) and
   [discussions](https://github.com/nafrucom/nafru-email-sdks/discussions).

## What to include

- SDK, SDK version and language / runtime version (e.g. `nafru-email 0.1.0`, Python 3.12).
- The error's `statusCode`, `name` and `message`, and the request id if the API returned one.
- A minimal code sample. **Remove API keys, tokens, webhook secrets and personal data** before posting.

## Response times

We aim to respond to new issues and questions within **2 business days**. Security reports are prioritized (see
[SECURITY.md](SECURITY.md)). Account and billing questions sent to destek@nafru.com are handled by the Nafru Email
support team.
