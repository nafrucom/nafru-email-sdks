# Contributing

Thanks for your interest in improving the Nafru Email SDKs!

This repository is **published automatically** from the Nafru Email monorepo on every release, so pull requests are not
merged here directly. They are still very welcome: we review them, port the change to the source repository and credit
you in the release notes.

## Good ways to help

- Report bugs with a minimal reproduction ([bug report](https://github.com/nafrucom/nafru-email-sdks/issues/new?template=bug_report.yml)).
- Improve documentation and examples.
- Suggest API ergonomics for your language ([feature request](https://github.com/nafrucom/nafru-email-sdks/issues/new?template=feature_request.yml)).

## Ground rules

- All SDKs must keep the **same features and behavior**; a change in one language usually needs the same change in the
  others.
- Keep runtime dependencies at zero where the standard library is enough.
- Add or update tests. Every SDK runs offline with a mocked transport:

| SDK    | Test command                                         |
| ------ | ---------------------------------------------------- |
| Python | `cd python && uv run --with pytest pytest`           |
| Go     | `cd go && go test -race ./...`                       |
| PHP    | `composer install && composer test`                  |
| Ruby   | `cd ruby && bundle install && bundle exec rake test` |
| Java   | `cd java && ./gradlew test`                          |
| .NET   | `cd dotnet && dotnet test`                           |
| Rust   | `cd rust && cargo test`                              |
| Swift  | `swift test`                                         |

- Never include real API keys, tokens or personal data in code, tests or issues.
- Security issues go through [SECURITY.md](SECURITY.md), not pull requests.

By participating you agree to our [Code of Conduct](CODE_OF_CONDUCT.md). Contributions are licensed under the
[MIT License](LICENSE).
