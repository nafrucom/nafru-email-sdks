# frozen_string_literal: true

require "openssl"

module Nafru
  module Email
    # Svix / Standard Webhooks uyumlu imza doğrulama.
    #
    #   imzalanan  = "#{svix-id}.#{svix-timestamp}.#{ham gövde}"
    #   anahtar    = `whsec_` sonrası base64 çözülmüş `signing_secret`
    #   başlık     = `v1,<base64 HMAC-SHA256>` (anahtar döndürmede boşlukla ayrılmış birden çok imza)
    module Webhook
      SECRET_PREFIX = "whsec_"
      DEFAULT_TOLERANCE_SECONDS = 300
      # Bir başlıkta en çok bu kadar imza denenir: aşırı uzun başlıkla CPU tüketilmesin.
      MAX_SIGNATURES = 32

      module_function

      # İmza ve zaman damgası geçerliyse `true`. Bozuk imza ya da zaman damgası `false`; bozuk `secret` ArgumentError fırlatır.
      #
      # @param payload [String] HAM istek gövdesi (bayt bayt; Rails'te `request.raw_post`): ayrıştırılıp yeniden dizilmiş JSON imzayı bozar.
      # @param headers [Hash] `{ id:, timestamp:, signature: }` (`svix-id`, `svix-timestamp`, `svix-signature`)
      # @param secret [String] webhook'un `signing_secret` değeri (`whsec_…`)
      # @param now [Time, Numeric] şimdiki zaman (Time ya da Unix saniyesi); testler için
      def verify(payload:, headers:, secret:, tolerance_seconds: DEFAULT_TOLERANCE_SECONDS, now: Time.now)
        raise ArgumentError, "Geçersiz imza anahtarı: whsec_ ile başlamalı" unless secret.start_with?(SECRET_PREFIX)

        key = begin
          secret.delete_prefix(SECRET_PREFIX).unpack1("m0")
        rescue ArgumentError
          raise ArgumentError, "Geçersiz imza anahtarı: base64 çözülemedi"
        end

        id, timestamp, signature = (headers || {}).to_h.transform_keys(&:to_sym).values_at(:id, :timestamp, :signature).map(&:to_s)
        return false if [id, timestamp, signature].any?(&:empty?)

        # Fark mutlak değerle alınır: hem eski hem gelecekteki zaman damgası reddedilir.
        stamp = Float(timestamp, exception: false)
        return false if stamp.nil? || !stamp.finite? || (now.to_i - stamp).abs > tolerance_seconds

        expected = OpenSSL::HMAC.digest("SHA256", key, "#{id}.#{timestamp}.#{payload}")
        signature.split(" ").first(MAX_SIGNATURES).any? do |candidate|
          version, value = candidate.split(",", 2)
          next false unless version == "v1" && value && !value.empty?

          mac = begin
            value.unpack1("m0")
          rescue ArgumentError
            next false
          end
          # Sabit zamanlı karşılaştırma (uzunluk gizli değil: HMAC-SHA256 hep 32 bayt).
          mac.bytesize == expected.bytesize && OpenSSL.fixed_length_secure_compare(mac, expected)
        end
      end
    end
  end
end
