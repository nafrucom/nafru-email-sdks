# frozen_string_literal: true

require "forwardable"

module Nafru
  module Email
    # Nafru Email üretim API'si; `base_url` verilmezse (ya da boşsa) kullanılır.
    DEFAULT_BASE_URL = "https://email.nafru.com/api"
  end
end

# API anahtarıyla istemci (Resend tarzı): `NafruEmail.new("nafru_...")`. Anahtar verilmezse `NAFRU_API_KEY` okunur.
class NafruEmail
  include Nafru::Email::Redacted

  attr_reader :emails, :domains, :contacts, :contact_properties, :segments, :topics, :broadcasts, :templates, :brand,
              :webhooks, :api_keys, :events

  # @param api_key [String, nil] Dashboard'dan üretilen API anahtarı; boşsa `NAFRU_API_KEY`. Tarayıcıya/istemciye gömmeyin.
  # @param base_url [String, nil] API'nin kök adresi; varsayılan `DEFAULT_BASE_URL` (yerelde `http://localhost:48787/api`).
  # @param transport [#call, nil] özel taşıyıcı (test, proxy); bkz. `NET_HTTP_TRANSPORT`.
  # @param max_retries [Integer] `429` ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme; `0` kapatır.
  # @param timeout [Numeric] istek başına zaman aşımı (saniye).
  # @param dev_outbox [String, false, nil] verilirse `emails.send`/`batch` göndermez, bu klasöre yazar;
  #   `nil`: `NODE_ENV=development` iken `.nafru/emails`; `false` her zaman gerçek gönderim.
  def initialize(api_key = nil, base_url: nil, transport: nil, max_retries: 2, timeout: 30, dev_outbox: nil)
    api_key = ENV.fetch("NAFRU_API_KEY", nil) if api_key.to_s.empty?
    raise ArgumentError, "Nafru SDK: api_key gerekli" if api_key.to_s.empty?
    base_url = Nafru::Email::DEFAULT_BASE_URL if base_url.to_s.empty?

    @http = Nafru::Email::Http.new(api_key: api_key, base_url: base_url, transport: transport, max_retries: max_retries, timeout: timeout)
    @emails = Nafru::Email::Resources::Emails.new(@http, Nafru::Email::DevOutbox.resolve(dev_outbox))
    @domains = Nafru::Email::Resources::Domains.new(@http)
    @contacts = Nafru::Email::Resources::Contacts.new(@http)
    @contact_properties = Nafru::Email::Resources::ContactProperties.new(@http)
    @segments = Nafru::Email::Resources::Segments.new(@http)
    @topics = Nafru::Email::Resources::Topics.new(@http)
    @broadcasts = Nafru::Email::Resources::Broadcasts.new(@http)
    @templates = Nafru::Email::Resources::Templates.new(@http)
    @brand = Nafru::Email::Resources::Brand.new(@http)
    @webhooks = Nafru::Email::Resources::Webhooks.new(@http)
    @api_keys = Nafru::Email::Resources::ApiKeys.new(@http)
    @events = Nafru::Email::Resources::Events.new(@http)
  end
end

# "Nafru ile bağlan" fabrikası: müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir.
# Tek alan adı/anahtar için `NafruEmail` kullanın.
class NafruConnect
  extend Forwardable
  include Nafru::Email::Redacted

  # `authorize_url(redirect_uri:, state:, scopes:, login_hint: nil)`, `exchange(code:, code_verifier:, redirect_uri:)`,
  # `revoke(refresh_token:)`: bkz. `Nafru::Email::Connect`.
  def_delegators :@connect, :authorize_url, :exchange, :revoke

  # @param client_secret [String] yalnız sunucunuzda.
  # @param base_url [String, nil] API'nin kök adresi; varsayılan `DEFAULT_BASE_URL`.
  # @param web_url [String, nil] izin ekranının kök adresi; verilmezse `base_url` sonundaki `/api` atılır.
  def initialize(client_id:, client_secret:, base_url: nil, web_url: nil, transport: nil, max_retries: 2, timeout: 30,
                 dev_outbox: nil)
    raise ArgumentError, "Nafru SDK: client_id gerekli" if client_id.to_s.empty?
    raise ArgumentError, "Nafru SDK: client_secret gerekli" if client_secret.to_s.empty?
    base_url = Nafru::Email::DEFAULT_BASE_URL if base_url.to_s.empty?

    @credentials = { client_id: client_id, client_secret: client_secret }
    @shared = { base_url: base_url, transport: transport, max_retries: max_retries, timeout: timeout }
    @dev_outbox = Nafru::Email::DevOutbox.resolve(dev_outbox)
    # Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
    @oauth = Nafru::Email::Http.new(**@shared, authorize: -> {})
    @connect = Nafru::Email::Connect.new(@oauth, **@credentials, web_url: web_url || base_url.sub(%r{/api/*\z}, ""))
  end

  # Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç `on_token_refresh` ile gelir.
  # @param on_token_refresh [#call] `{ refresh_token: }` alır; yeni değeri KALICI yazmadan eskisi geçersizdir. Hata fırlatırsa
  #   çağrı `token_persist_failed` ile hata verir. Blok olarak da verilebilir.
  def connection(connection_id, refresh_token:, on_token_refresh: nil, &block)
    callback = on_token_refresh || block or raise ArgumentError, "Nafru SDK: on_token_refresh gerekli"
    tokens = Nafru::Email::TokenManager.new(@oauth, **@credentials, refresh_token: refresh_token, on_token_refresh: callback)
    Nafru::Email::Connection.new(connection_id, tokens: tokens, dev_outbox: @dev_outbox,
                                  http_factory: ->(authorize) { Nafru::Email::Http.new(**@shared, authorize: authorize) })
  end
end
