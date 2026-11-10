# frozen_string_literal: true

require_relative "test_helper"

class AppTest < Minitest::Test
  def server(&route)
    transport = FakeTransport.new(&route)
    app = NafruConnect.new(client_id: "app_x", client_secret: "nfs_secret", base_url: "https://api.test/",
                                web_url: "https://web.test", transport: transport, max_retries: 0, dev_outbox: false)
    [app, transport]
  end

  def token(n) = json_response({ access_token: "nfa_#{n}", refresh_token: "nfr_#{n}", token_type: "Bearer", expires_in: 3600,
                                 connection_id: "conn_1", scopes: ["emails.send"] })

  def oauth_calls(transport) = transport.calls.select { |call| call.url.end_with?("/oauth/token") }
  def api_calls(transport) = transport.calls.reject { |call| call.url.include?("/oauth/") }

  def open(saved = [], &route)
    app, transport = server(&route)
    connection = app.connection("conn_1", refresh_token: "nfr_0") { |tokens| saved << tokens[:refresh_token] }
    [connection, transport, saved]
  end

  def test_pkce
    pkce = Nafru::Email.create_pkce
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, pkce[:verifier])
    expected = [OpenSSL::Digest::SHA256.digest(pkce[:verifier])].pack("m0").tr("+/", "-_").delete("=")
    assert_equal expected, pkce[:challenge]
    refute_equal pkce[:verifier], Nafru::Email.create_pkce[:verifier]
  end

  def test_authorize_url
    app, = server { json_response({}) }
    result = app.authorize_url(redirect_uri: "https://scout.test/cb", state: "st1",
                                       scopes: %w[emails.send templates.read], login_hint: "a@b.co")
    uri = URI(result[:url])
    assert_equal "https://web.test/connect", "#{uri.scheme}://#{uri.host}#{uri.path}"
    params = URI.decode_www_form(uri.query).to_h
    assert_equal({ "client_id" => "app_x", "redirect_uri" => "https://scout.test/cb", "state" => "st1",
                   "scope" => "emails.send templates.read", "code_challenge_method" => "S256", "login_hint" => "a@b.co" },
                 params.except("code_challenge"))
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, params["code_challenge"])
    assert_match(/\A[A-Za-z0-9_-]{43}\z/, result[:code_verifier])
    assert_raises(ArgumentError) { app.authorize_url(redirect_uri: "x", state: "", scopes: ["emails.send"]) }
    assert_raises(ArgumentError) { app.authorize_url(redirect_uri: "x", state: "s", scopes: []) }
  end

  def test_web_url_defaults_to_base_without_api
    app = NafruConnect.new(client_id: "a", client_secret: "s", base_url: "https://email.ornek.com/api/")
    url = app.authorize_url(redirect_uri: "r", state: "s", scopes: ["emails.send"])[:url]
    assert url.start_with?("https://email.ornek.com/connect?")
  end

  def test_default_base_url_and_web_url
    transport = FakeTransport.new { token(1) }
    app = NafruConnect.new(client_id: "a", client_secret: "s", transport: transport)
    url = app.authorize_url(redirect_uri: "r", state: "s", scopes: ["emails.send"])[:url]
    assert url.start_with?("https://email.nafru.com/connect?")
    app.exchange(code: "c", code_verifier: "v", redirect_uri: "r")
    assert_equal "https://email.nafru.com/api/oauth/token", transport.calls.first.url
  end

  def test_oauth_methods_live_directly_on_nafru_connect
    app, = server { json_response({}) }
    refute_respond_to app, :connect
    %i[authorize_url exchange revoke connection].each { |name| assert_respond_to app, name }
  end

  def test_exchange_and_revoke_without_authorization_header
    app, transport = server { token(1) }
    grant = app.exchange(code: "nfc_1", code_verifier: "v" * 43, redirect_uri: "https://scout.test/cb")
    assert_equal({ connection_id: "conn_1", refresh_token: "nfr_1", scopes: ["emails.send"] }, grant.to_h)
    assert_equal "nfr_1", grant[:refresh_token]
    call = transport.calls.first
    assert_equal ["https://api.test/oauth/token", "POST", nil], [call.url, call.method, call.headers["authorization"]]
    assert_equal({ "grant_type" => "authorization_code", "client_id" => "app_x", "client_secret" => "nfs_secret",
                   "code" => "nfc_1", "code_verifier" => "v" * 43, "redirect_uri" => "https://scout.test/cb" }, call.json)

    assert_nil app.revoke(refresh_token: "nfr_1")
    assert_equal({ "client_id" => "app_x", "client_secret" => "nfs_secret", "token" => "nfr_1" }, transport.calls.last.json)
  end

  def test_exchange_error_raises
    app, = server { json_response({ statusCode: 400, name: "invalid_grant", message: "invalid" }, status: 400) }
    error = assert_raises(Nafru::Email::Error) { app.exchange(code: "c", code_verifier: "v", redirect_uri: "r") }
    assert_equal [400, "invalid_grant"], [error.status_code, error.name]
  end

  def test_first_call_refreshes_and_persists_rotated_token
    connection, transport, saved = open { |call| call.url.end_with?("/oauth/token") ? token(1) : json_response({ ready: true }) }
    assert_equal({ ready: true }, connection.status)
    assert_equal ["nfr_1"], saved
    assert_equal({ "grant_type" => "refresh_token", "client_id" => "app_x", "client_secret" => "nfs_secret",
                   "refresh_token" => "nfr_0" }, transport.calls.first.json)
    assert_equal ["https://api.test/connection", "Bearer nfa_1"], api_calls(transport).map { [_1.url, _1.headers["authorization"]] }.first
  end

  def test_concurrent_calls_share_single_refresh
    connection, transport, saved = open do |call|
      if call.url.end_with?("/oauth/token")
        sleep 0.05
        token(1)
      else
        json_response({ ready: true })
      end
    end
    results = Array.new(5) { Thread.new { connection.status } }.map(&:value)
    assert(results.all? { _1 == { ready: true } })
    assert_equal 1, oauth_calls(transport).size
    assert_equal ["nfr_1"], saved
    connection.status
    assert_equal 1, oauth_calls(transport).size
  end

  def test_invalid_token_refreshes_once_and_retries
    refreshes = 0
    connection, transport, = open do |call|
      next token(refreshes += 1) if call.url.end_with?("/oauth/token")

      if call.headers["authorization"] == "Bearer nfa_1"
        json_response({ statusCode: 401, name: "invalid_token", message: "expired" }, status: 401)
      else
        json_response({ ready: true })
      end
    end
    assert_equal({ ready: true }, connection.status)
    assert_equal 2, refreshes
    assert_equal ["Bearer nfa_1", "Bearer nfa_2"], api_calls(transport).map { _1.headers["authorization"] }
  end

  def test_rejected_refresh_maps_to_connection_revoked
    connection, transport, = open { json_response({ statusCode: 400, name: "invalid_grant", message: "x" }, status: 400) }
    error = assert_raises(Nafru::Email::Error) { connection.status }
    assert_equal "connection_revoked", error.name
    assert_empty api_calls(transport)

    connection, = open { json_response({ statusCode: 403, name: "forbidden", message: "x" }, status: 403) }
    assert_equal "connection_revoked", assert_raises(Nafru::Email::Error) { connection.status }.name
  end

  def test_persist_failure_is_retried_on_next_call_without_new_refresh
    app, transport = server { token(1) }
    saved = []
    failures = 1
    connection = app.connection("conn_1", refresh_token: "nfr_0", on_token_refresh: lambda { |tokens|
      raise "disk dolu" if (failures -= 1) >= 0

      saved << tokens[:refresh_token]
    })
    error = assert_raises(Nafru::Email::Error) { connection.status }
    assert_equal "token_persist_failed", error.name
    assert_includes error.message, "disk dolu"
    connection.status
    assert_equal ["nfr_1"], saved
    assert_equal 1, oauth_calls(transport).size
  end

  def test_connection_surface
    connection, transport, = open do |call|
      call.url.end_with?("/oauth/token") ? token(1) : json_response({ id: "e1", data: [] })
    end
    connection.senders.list
    connection.templates.list
    connection.emails.send({ from: "a@b.co", to: ["c@d.co"], subject: "s", html: "<p>x</p>" }, idempotency_key: "k1")
    connection.emails.get("e1")
    connection.emails.list
    assert_equal ["GET /senders", "GET /templates", "POST /emails", "GET /emails/e1", "GET /emails"],
                 api_calls(transport).map { "#{_1.method} #{_1.path}" }
    assert_equal "k1", api_calls(transport)[2].headers["idempotency-key"]
    assert_equal "conn_1", connection.id
    refute_respond_to connection.emails, :batch
  end

  def test_server_error_raises
    connection, = open do |call|
      call.url.end_with?("/oauth/token") ? token(1) : json_response({ statusCode: 403, name: "insufficient_scope", message: "scope" }, status: 403)
    end
    error = assert_raises(Nafru::Email::Error) { connection.templates.list }
    assert_equal [403, "insufficient_scope"], [error.status_code, error.name]
  end
end
