# frozen_string_literal: true

require "ipaddr"
require "json"
require "net/http"
require "uri"

module Nafru
  module Email
    # Taşıyıcının döndürdüğü yanıt. `headers` anahtarları küçük harf olmalıdır.
    Response = Struct.new(:status, :headers, :body, :reason, keyword_init: true)

    # Yanıt gövdesi üst sınırı: bozuk ya da kötü niyetli bir ara katman belleği tüketemesin.
    MAX_RESPONSE_BYTES = 10 * 1024 * 1024

    def self.response_too_large = Error.new("Yanıt gövdesi #{MAX_RESPONSE_BYTES} baytı aşıyor", name: "response_too_large")

    # Varsayılan taşıyıcı (Net::HTTP). Özel taşıyıcı aynı imzayla `call` yanıtlayan herhangi bir nesnedir.
    # Net::HTTP yönlendirme izlemez ve TLS sertifikasını doğrular (VERIFY_PEER); bunu kapatan bir seçenek yoktur.
    # shortcut: her istek yeni bağlantı açar (keep-alive yok); yüksek hacimde kalıcı bağlantılı bir taşıyıcı verin.
    NET_HTTP_TRANSPORT = lambda do |method:, url:, headers:, body:, timeout:|
      uri = URI(url)
      request = Net::HTTPGenericRequest.new(method, !body.nil?, true, uri.request_uri, headers)
      request.body = body
      Net::HTTP.start(uri.hostname, uri.port, use_ssl: uri.scheme == "https",
                                              open_timeout: timeout, read_timeout: timeout, write_timeout: timeout) do |conn|
        conn.request(request) do |response|
          buffer = +""
          response.read_body do |chunk|
            buffer << chunk
            raise Email.response_too_large if buffer.bytesize > MAX_RESPONSE_BYTES
          end
          return Response.new(status: response.code.to_i, headers: response.each_header.to_h, body: buffer,
                              reason: response.message)
        end
      end
    end

    # http yalnız geri döngü/yerel adreslerde serbest: düz metin üzerinde API anahtarı ve belirteç taşınmasın.
    def self.require_https!(url, label)
      uri = URI(url)
      host = uri.hostname.to_s.downcase
      local = host == "localhost" || host.end_with?(".localhost") || (begin
        IPAddr.new(host).loopback?
      rescue IPAddr::Error
        false
      end)
      return if uri.scheme == "https" || (uri.scheme == "http" && local)

      raise ArgumentError, "Nafru SDK: #{label} https kullanmalı (http yalnız localhost için)"
    rescue URI::InvalidURIError
      raise ArgumentError, "Nafru SDK: #{label} geçerli bir adres değil"
    end

    # `Http`, `Connect` vb. sırları (anahtar, belirteç) tutar: `inspect`/`pp` çıktısına girmesinler.
    module Redacted
      def inspect = "#<#{self.class.name} [REDACTED]>"
      alias to_s inspect
    end

    # İstek katmanı: kimlik, yeniden deneme, zaman aşımı, hata ayrıştırma.
    class Http
      include Redacted

      MAX_BACKOFF = 8.0
      BASE_BACKOFF = 0.3

      # @param authorize [#call, nil] verilirse `api_key` yerine her denemede bundan alınan belirteç kullanılır (`nil`: başlık yok).
      def initialize(base_url:, api_key: nil, authorize: nil, transport: nil, max_retries: 2, timeout: 30, user_agent: nil)
        Email.require_https!(base_url, "base_url")
        @base = base_url.sub(%r{/+\z}, "")
        @api_key = api_key
        @authorize = authorize
        @transport = transport || NET_HTTP_TRANSPORT
        @max_retries = max_retries
        @timeout = timeout
        @user_agent = user_agent || "nafru-email-ruby/#{VERSION}"
      end

      def self.serialize_query(query)
        pairs = (query || {}).reject { |_, value| value.nil? || value == "" }.map { |key, value| [key.to_s, value.to_s] }
        pairs.empty? ? "" : "?#{URI.encode_www_form(pairs)}"
      end

      # Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) güvenle kaçırılır (encodeURIComponent).
      # Boş, `.` ve `..` reddedilir: URL normalleştirmesi bunları başka bir uca çevirirdi.
      def self.seg(value)
        text = value.to_s
        raise ArgumentError, "Nafru SDK: yol parçası boş, '.' ya da '..' olamaz" if ["", ".", ".."].include?(text)

        text.b.gsub(%r{[^A-Za-z0-9\-_.!~*'()]}) { |char| format("%%%02X", char.ord) }
      end

      # @return [Object] ayrıştırılmış JSON (sembol anahtarlı) ya da boş gövdede `nil`
      # @raise [Error]
      def request(method, path, query: nil, body: nil, idempotency_key: nil)
        headers = { "accept" => "application/json", "user-agent" => @user_agent }
        headers["authorization"] = "Bearer #{@api_key}" unless @authorize
        payload = nil
        unless body.nil?
          payload = JSON.generate(body)
          headers["content-type"] = "application/json"
        end
        unless idempotency_key.nil?
          # Başlık enjeksiyonu: CR/LF ya da başka denetim karakteri başlığa giremez.
          if idempotency_key.to_s.empty? || idempotency_key.to_s.match?(/[[:cntrl:]]/)
            raise ArgumentError, "Nafru SDK: idempotency_key boş olamaz ve denetim karakteri içeremez"
          end

          headers["idempotency-key"] = idempotency_key.to_s
        end
        url = "#{@base}#{path}#{self.class.serialize_query(query)}"
        # `GET`/`DELETE` yinelenebilir; `POST`/`PATCH` yalnız 429'da ya da `Idempotency-Key` varsa: anahtarsız sunucu hatasında e-posta çift gidebilir.
        safe = %w[GET DELETE].include?(method) || !idempotency_key.nil?

        attempt = 0
        loop do
          if @authorize
            token = @authorize.call
            token.nil? ? headers.delete("authorization") : headers["authorization"] = "Bearer #{token}"
          end
          last = attempt >= @max_retries

          begin
            response = @transport.call(method: method, url: url, headers: headers.dup, body: payload, timeout: @timeout)
          rescue Error
            raise
          rescue StandardError => e
            if !last && safe
              pause([BASE_BACKOFF * (2**attempt), MAX_BACKOFF].min)
              attempt += 1
              next
            end
            raise e.is_a?(Timeout::Error) ? Error.timeout(@timeout) : Error.network(e.message.to_s.empty? ? "Sunucuya ulaşılamadı" : e.message)
          end

          raise Email.response_too_large if response.body.to_s.bytesize > MAX_RESPONSE_BYTES

          # API hiç yönlendirmez; izlemek `Authorization`'ı başka bir sunucuya sızdırabilir. Yeniden denenmez.
          if response.status.between?(300, 399)
            raise Error.new("Beklenmeyen yönlendirme (HTTP #{response.status}); izlenmedi", name: "unexpected_redirect",
                                                                                            status_code: response.status)
          end

          response_headers = (response.headers || {}).transform_keys { |key| key.to_s.downcase }
          warn_deprecated(response_headers)
          data = parse_body(response.body)
          return data if response.status.between?(200, 299)

          error = Error.parse(response.status, response_headers, data, response.reason)
          retryable = response.status == 429 || (response.status >= 500 && safe)
          raise error unless retryable && !last

          pause([error.retry_after || (BASE_BACKOFF * (2**attempt)), MAX_BACKOFF].min)
          attempt += 1
        end
      end

      private

      def pause(seconds) = sleep(seconds)

      # Sunucu bu SDK sürümünü kullanımdan kaldırdıysa istemci başına bir kez uyarır; çağrıyı asla bozmaz.
      def warn_deprecated(headers)
        return if @deprecation_warned || !headers.key?("deprecation")

        @deprecation_warned = true
        message = +"[nafru] Bu SDK sürümü (ruby #{VERSION}) kullanımdan kaldırıldı; lütfen güncelleyin."
        message << " Son tarih: #{headers['sunset']}" if headers["sunset"]
        link = headers["link"].to_s[/<([^>]+)>/, 1] || headers["link"]
        message << " Ayrıntı: #{link}" if link && !link.empty?
        warn message
      end

      def parse_body(text)
        return nil if text.nil? || text.empty?

        JSON.parse(text, symbolize_names: true)
      rescue JSON::ParserError
        nil
      end
    end
  end
end
