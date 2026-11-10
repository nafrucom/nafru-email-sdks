# frozen_string_literal: true

require "openssl"
require "securerandom"
require "uri"

module Nafru
  module Email
    # Uygulamanın müşteriden isteyebileceği izinler.
    SCOPES = %w[emails.send emails.read templates.read domains.read senders.read connection.read].freeze

    def self.base64url(bytes) = [bytes].pack("m0").tr("+/", "-_").delete("=")

    # PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması.
    # @return [Hash] `{ verifier:, challenge: }`
    def self.create_pkce
      verifier = base64url(SecureRandom.random_bytes(32))
      { verifier: verifier, challenge: base64url(OpenSSL::Digest::SHA256.digest(verifier)) }
    end

    # `exchange` sonucu. `inspect`/`to_s` yenileme belirtecini göstermez; değere `grant.refresh_token` ya da `grant[:refresh_token]` ile erişin.
    ConnectionGrant = Struct.new(:connection_id, :refresh_token, :scopes, keyword_init: true) do
      def inspect = "#<ConnectionGrant connection_id=#{connection_id.inspect} refresh_token=[REDACTED] scopes=#{scopes.inspect}>"
      alias_method :to_s, :inspect

      def pretty_print(pp) = pp.text(inspect)
    end

    # "Nafru ile bağlan" uçları: izin adresi, kod değişimi, iptal.
    class Connect
      include Redacted

      def initialize(oauth, client_id:, client_secret:, web_url:)
        @oauth = oauth
        @client_id = client_id
        @client_secret = client_secret
        Email.require_https!(web_url, "web_url")
        @web = web_url.sub(%r{/+\z}, "")
      end

      # Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. `code_verifier`'ı oturumda saklayın; dönüşte `exchange`'e verin.
      # Dönüşte `state`'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
      # @return [Hash] `{ url:, code_verifier: }`
      def authorize_url(redirect_uri:, state:, scopes:, login_hint: nil)
        raise ArgumentError, "Nafru SDK: state gerekli (CSRF koruması)" if state.to_s.empty?
        raise ArgumentError, "Nafru SDK: en az bir izin (scopes) gerekli" if scopes.empty?

        pkce = Email.create_pkce
        params = {
          client_id: @client_id, redirect_uri: redirect_uri, state: state, scope: scopes.join(" "),
          code_challenge: pkce[:challenge], code_challenge_method: "S256"
        }
        params[:login_hint] = login_hint if login_hint && !login_hint.empty?
        { url: "#{@web}/connect?#{URI.encode_www_form(params)}", code_verifier: pkce[:verifier] }
      end

      # Dönüşteki tek kullanımlık `code`'u bağlantıya çevirir (sunucunuzdan çağırın).
      # @return [ConnectionGrant]
      def exchange(code:, code_verifier:, redirect_uri:)
        data = @oauth.request("POST", "/oauth/token", body: {
          grant_type: "authorization_code", client_id: @client_id, client_secret: @client_secret,
          code: code, code_verifier: code_verifier, redirect_uri: redirect_uri
        })
        ConnectionGrant.new(connection_id: data[:connection_id], refresh_token: data[:refresh_token], scopes: data[:scopes])
      end

      # Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur.
      def revoke(refresh_token:)
        @oauth.request("POST", "/oauth/revoke", body: { client_id: @client_id, client_secret: @client_secret, token: refresh_token })
        nil
      end
    end

    # Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş): dönüşlü yenileme
    # belirteci ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
    class TokenManager
      include Redacted

      # Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).
      EARLY_REFRESH = 30

      def initialize(oauth, client_id:, client_secret:, refresh_token:, on_token_refresh:)
        @oauth = oauth
        @client_id = client_id
        @client_secret = client_secret
        @refresh_token = refresh_token
        @on_token_refresh = on_token_refresh
        @access_token = nil
        @expires_at = 0
        # Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı.
        @unpersisted = false
        @mutex = Mutex.new
      end

      # Geçerli erişim belirteci; yoksa ya da dolmak üzereyse yeniler. Kilit, bekleyenlerin tek yenilemenin sonucunu görmesini sağlar.
      def access_token
        @mutex.synchronize do
          persist if @unpersisted
          return @access_token if @access_token && now < @expires_at - EARLY_REFRESH

          refresh
        end
      end

      # Sunucu 401 `invalid_token` dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır).
      def invalidate(stale)
        @mutex.synchronize do
          @access_token = nil if @access_token == stale
          @access_token || refresh
        end
      end

      private

      def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

      def persist
        @on_token_refresh.call({ refresh_token: @refresh_token })
        @unpersisted = false
      rescue StandardError => e
        @unpersisted = true
        raise Error.new("Yeni yenileme belirteci saklanamadı: #{e.message}", name: "token_persist_failed")
      end

      def refresh
        data = begin
          @oauth.request("POST", "/oauth/token", body: {
            grant_type: "refresh_token", client_id: @client_id, client_secret: @client_secret, refresh_token: @refresh_token
          })
        rescue Error => e
          # Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
          raise e unless %w[invalid_grant connection_revoked].include?(e.name) ||
                         (e.status_code == 403 && e.name != "rate_limit_exceeded")

          raise Error.new("Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir.",
                          name: "connection_revoked", status_code: e.status_code, errors: e.errors, retry_after: e.retry_after)
        end
        @refresh_token = data[:refresh_token]
        @access_token = data[:access_token]
        @expires_at = now + data[:expires_in].to_f
        persist
        @access_token
      end
    end

    # Bir müşteri bağlantısı adına çağrı yapar. Her denemede `TokenManager#access_token` ile belirteç alınır; 401 `invalid_token`
    # (süre dolmuş / yenilenmiş) ise bir kez yenileyip tekrar dener.
    class Connection
      include Redacted

      attr_reader :id, :senders, :templates, :emails

      # Bağlantı istemcisinde yalnız gönderim ve okuma vardır.
      class Emails
        def initialize(emails) = @emails = emails
        def send(...) = @emails.send(...)
        def get(...) = @emails.get(...)
        def list(...) = @emails.list(...)
      end

      Senders = Struct.new(:conn) do
        def list = conn.request("GET", "/senders")
      end

      # Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kendi kopyası paketi gölgeler).
      Templates = Struct.new(:conn) do
        def list = conn.request("GET", "/templates")
      end

      def initialize(id, tokens:, http_factory:, dev_outbox: false)
        @id = id
        @tokens = tokens
        @current = nil
        @http = http_factory.call(lambda {
          @current = @tokens.access_token
        })
        @senders = Senders.new(self)
        @templates = Templates.new(self)
        @emails = Emails.new(Resources::Emails.new(self, dev_outbox))
      end

      # `GET /connection`: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.
      def status = request("GET", "/connection")

      # @api private
      def request(method, path, **options)
        @http.request(method, path, **options)
      rescue Error => e
        raise unless e.name == "invalid_token" && @current

        @tokens.invalidate(@current)
        @http.request(method, path, **options)
      end
    end
  end
end
