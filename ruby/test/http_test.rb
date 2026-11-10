# frozen_string_literal: true

require_relative "test_helper"

class HttpTest < Minitest::Test
  def test_sends_auth_user_agent_json_and_idempotency_key
    client, transport, = setup_client([json_response({ id: "e1" })])
    data = client.emails.send({ from: "a@x.test", to: "b@x.test", subject: "s", text: "t" }, idempotency_key: "k-1")
    assert_equal({ id: "e1" }, data)
    call = transport.calls.first
    assert_equal "https://api.test/emails", call.url
    assert_equal "POST", call.method
    assert_equal "Bearer key_test", call.headers["authorization"]
    assert_equal "application/json", call.headers["content-type"]
    assert_equal "k-1", call.headers["idempotency-key"]
    assert_equal "nafru-email-ruby/#{Nafru::Email::VERSION}", call.headers["user-agent"]
    assert_equal({ "from" => "a@x.test", "to" => "b@x.test", "subject" => "s", "text" => "t" }, call.json)
  end

  def test_query_skips_nil_and_empty
    client, transport, = setup_client([json_response({ object: "list", data: [], has_more: false })])
    client.contacts.list(limit: 5, after: nil, before: "", search: "ali veli")
    assert_equal "https://api.test/contacts?limit=5&search=ali+veli", transport.calls.first.url
  end

  def test_path_segments_are_encoded
    client, transport, = setup_client([json_response({})])
    client.contacts.get("ali+x@ornek.com")
    assert_equal "https://api.test/contacts/ali%2Bx%40ornek.com", transport.calls.first.url
  end

  def test_parses_error_body
    body = { statusCode: 422, name: "validation_error", message: "Geçersiz",
             errors: [{ field: "to", message: "zorunlu", i18nTranslationKey: "k" }] }
    client, = setup_client([json_response(body, status: 422)])
    error = assert_raises(Nafru::Email::Error) { client.emails.send({ to: "x", text: "t" }) }
    assert_equal({ status_code: 422, name: "validation_error", message: "Geçersiz", errors: body[:errors] }, error.to_h)
  end

  def test_non_standard_body_falls_back_to_status
    bad = Nafru::Email::Response.new(status: 502, headers: {}, body: "<html>bad</html>", reason: "Bad Gateway")
    client, = setup_client([bad])
    error = assert_raises(Nafru::Email::Error) { client.emails.get("e1") }
    assert_equal [502, "application_error", "Bad Gateway"], [error.status_code, error.name, error.message]
    error = assert_raises(Nafru::Email::Error) { setup_client([json_response({}, status: 404)])[0].emails.get("e1") }
    assert_equal ["not_found", "HTTP 404"], [error.name, error.message]
  end

  def test_network_error_has_nil_status
    client, = setup_client([-> { raise SocketError, "bağlanamadı" }])
    error = assert_raises(Nafru::Email::Error) { client.emails.send({ to: "x", text: "t" }) }
    assert_equal({ status_code: nil, name: "application_error", message: "bağlanamadı" }, error.to_h)
  end

  def test_timeout_error
    client, = setup_client([-> { raise Net::ReadTimeout }])
    error = assert_raises(Nafru::Email::Error) { client.emails.get("e1") }
    assert_nil error.status_code
    assert_equal "timeout_error", error.name
  end

  def test_429_retried_with_retry_after_even_for_post
    limited = json_response({ statusCode: 429, name: "rate_limit_exceeded", message: "yavaş" }, status: 429,
                                                                                               headers: { "Retry-After" => "3" })
    client, transport, waits = setup_client([limited, json_response({ id: "e1" })], max_retries: 2)
    assert_equal({ id: "e1" }, client.emails.send({ to: "x", text: "t" }))
    assert_equal 2, transport.calls.size
    assert_equal [3], waits
  end

  def test_429_exhausted_raises_with_retry_after_capped_wait
    limited = json_response({ statusCode: 429, name: "rate_limit_exceeded", message: "yavaş" }, status: 429,
                                                                                               headers: { "retry-after" => "60" })
    client, transport, waits = setup_client([limited], max_retries: 1)
    error = assert_raises(Nafru::Email::Error) { client.emails.get("e1") }
    assert_equal [429, "rate_limit_exceeded", 60], [error.status_code, error.name, error.retry_after]
    assert_equal 2, transport.calls.size
    assert_equal [8.0], waits
  end

  def test_get_5xx_retried_post_without_key_not
    down = json_response({ statusCode: 500, name: "application_error", message: "x" }, status: 500)
    client, transport, waits = setup_client([down, json_response({ id: "e1" })], max_retries: 1)
    assert_equal "e1", client.emails.get("e1")[:id]
    assert_equal 2, transport.calls.size
    assert_equal [0.3], waits

    client, transport, = setup_client([down, json_response({ id: "e1" })], max_retries: 1)
    error = assert_raises(Nafru::Email::Error) { client.emails.send({ to: "x", text: "t" }) }
    assert_equal 500, error.status_code
    assert_equal 1, transport.calls.size
  end

  def test_post_with_idempotency_key_retried_after_5xx
    down = json_response({ statusCode: 503, name: "application_error", message: "x" }, status: 503)
    client, transport, = setup_client([down, json_response({ id: "e1" })], max_retries: 1)
    assert_equal({ id: "e1" }, client.emails.send({ to: "x", text: "t" }, idempotency_key: "k-1"))
    assert_equal 2, transport.calls.size
    assert_equal "k-1", transport.calls[1].headers["idempotency-key"]
  end

  def with_env(name, value)
    previous = ENV.fetch(name, nil)
    ENV[name] = value
    yield
  ensure
    ENV[name] = previous
  end

  def test_api_key_from_env_when_omitted
    with_env("NAFRU_API_KEY", "nafru_env") do
      [[], [nil], [""]].each do |args|
        transport = FakeTransport.new([json_response({})])
        NafruEmail.new(*args, transport: transport, dev_outbox: false).emails.get("e1")
        assert_equal "Bearer nafru_env", transport.calls.first.headers["authorization"]
      end
    end
  end

  def test_api_key_required_base_url_defaults
    with_env("NAFRU_API_KEY", nil) { assert_raises(ArgumentError) { NafruEmail.new("", base_url: "https://x") } }
    [nil, ""].each do |base_url|
      transport = FakeTransport.new([json_response({})])
      NafruEmail.new("k", base_url: base_url, transport: transport, dev_outbox: false).emails.get("e1")
      assert_equal "https://email.nafru.com/api/emails/e1", transport.calls.first.url
    end
    assert_equal "https://email.nafru.com/api", Nafru::Email::DEFAULT_BASE_URL
  end
end

class DeprecationTest < Minitest::Test
  def test_warns_once_on_deprecation_header_without_failing
    headers = { "Deprecation" => "true", "Sunset" => "Wed, 01 Jul 2027 00:00:00 GMT",
                "Link" => '<https://nafru.com/sdk>; rel="deprecation"' }
    client, = setup_client([json_response({ id: "e1" }, headers: headers)])
    _, err = capture_io do
      assert_equal({ id: "e1" }, client.emails.get("e1"))
      client.emails.get("e1")
    end
    assert_equal "[nafru] Bu SDK sürümü (ruby #{Nafru::Email::VERSION}) kullanımdan kaldırıldı; lütfen güncelleyin. " \
                 "Son tarih: Wed, 01 Jul 2027 00:00:00 GMT Ayrıntı: https://nafru.com/sdk\n", err
  end
end

class SecurityTest < Minitest::Test
  def test_https_required_except_loopback
    ["http://api.example.com/api", "ftp://api.test", "http://localhost.evil.com"].each do |url|
      error = assert_raises(ArgumentError) { NafruEmail.new("k", base_url: url) }
      assert_includes error.message, "https"
    end
    ["http://localhost:48787/api", "http://app.localhost", "http://127.0.0.1:1", "http://127.9.9.9", "http://[::1]:80/api",
     "https://email.nafru.com/api"].each { |url| NafruEmail.new("k", base_url: url) }
    assert_raises(ArgumentError) { NafruConnect.new(client_id: "a", client_secret: "s", web_url: "http://web.example.com") }
    assert_raises(ArgumentError) { NafruConnect.new(client_id: "a", client_secret: "s", base_url: "http://api.example.com") }
  end

  def test_redirect_is_error_and_not_retried
    redirect = Nafru::Email::Response.new(status: 302, headers: { "location" => "https://evil.test/" }, body: "")
    client, transport, = setup_client([redirect, json_response({ id: "e1" })], max_retries: 2)
    error = assert_raises(Nafru::Email::Error) { client.emails.get("e1") }
    assert_equal [302, "unexpected_redirect"], [error.status_code, error.name]
    assert_equal 1, transport.calls.size
  end

  def test_unsafe_path_segments_rejected_before_request
    client, transport, = setup_client([json_response({})])
    ["", ".", "..", nil].each do |id|
      assert_raises(ArgumentError) { client.emails.get(id) }
      assert_raises(ArgumentError) { client.templates.remove_translation("welcome", id) }
    end
    assert_empty transport.calls
    client.contacts.get("..a")
    assert_equal "https://api.test/contacts/..a", transport.calls.first.url
  end

  def test_idempotency_key_rejects_control_characters
    client, transport, = setup_client([json_response({ id: "e1" })])
    ["", "a\r\nX-Evil: 1", "a\nb", "a\tb", "a\u0000b"].each do |key|
      assert_raises(ArgumentError) { client.emails.send({ to: "x", text: "t" }, idempotency_key: key) }
    end
    assert_empty transport.calls
  end

  def test_response_too_large
    huge = Nafru::Email::Response.new(status: 200, headers: {}, body: "a" * (Nafru::Email::MAX_RESPONSE_BYTES + 1))
    client, = setup_client([huge])
    assert_equal "response_too_large", assert_raises(Nafru::Email::Error) { client.emails.get("e1") }.name
  end

  def test_secrets_are_redacted_in_inspect_and_pp
    require "pp"
    client = NafruEmail.new("nafru_supersecret")
    connect = NafruConnect.new(client_id: "app_x", client_secret: "nfs_supersecret")
    connection = connect.connection("conn_1", refresh_token: "nfr_supersecret") { nil }
    grant = Nafru::Email::ConnectionGrant.new(connection_id: "conn_1", refresh_token: "nfr_supersecret", scopes: [])
    [client, connect, connection, grant].each do |object|
      [object.inspect, object.to_s, object.pretty_inspect, "#{object}", [object].inspect, { k: object }.inspect].each do |text|
        refute_match(/supersecret/, text)
      end
    end
    assert_includes grant.inspect, "conn_1"
  end
end
