# frozen_string_literal: true

module Nafru
  module Email
    # Her başarısız çağrının fırlattığı hata. `status_code` ağ hatalarında `nil`'dır. `name`, sunucunun hata adıdır
    # (`validation_error`, `rate_limit_exceeded`, `not_found`, …); ağ ve zaman aşımı için `application_error` / `timeout_error`.
    class Error < StandardError
      NAMES_BY_STATUS = {
        400 => "invalid_request",
        401 => "unauthorized",
        403 => "forbidden",
        404 => "not_found",
        409 => "conflict",
        413 => "payload_too_large",
        422 => "validation_error",
        429 => "rate_limit_exceeded"
      }.freeze

      # @return [Integer, nil]
      attr_reader :status_code
      # @return [String]
      attr_reader :name
      # @return [Array<Hash>, nil] 422'de alan ayrıntısı: `{ field:, message:, i18nTranslationKey: }`
      attr_reader :errors
      # @return [Numeric, nil] `429` yanıtındaki `retry-after` (saniye)
      attr_reader :retry_after

      def initialize(message, name:, status_code: nil, errors: nil, retry_after: nil)
        super(message)
        @name = name
        @status_code = status_code
        @errors = errors
        @retry_after = retry_after
      end

      def to_h
        { status_code: status_code, name: name, message: message, errors: errors, retry_after: retry_after }
          .reject { |key, value| value.nil? && key != :status_code }
      end

      def self.network(message) = new(message, name: "application_error")

      def self.timeout(seconds) = new("İstek #{seconds} sn içinde tamamlanmadı", name: "timeout_error")

      # Standart gövde (`statusCode`, `name`, `message`, `errors`) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde).
      def self.parse(status, headers, body, reason = nil)
        raw = headers["retry-after"]
        retry_after = raw && Float(raw, exception: false)
        retry_after = nil if retry_after&.negative?
        retry_after = retry_after.to_i if retry_after && retry_after == retry_after.to_i
        fallback = NAMES_BY_STATUS.fetch(status, "application_error")
        unless body.is_a?(Hash) && body[:message].is_a?(String)
          return new(reason.to_s.empty? ? "HTTP #{status}" : reason, name: fallback, status_code: status, retry_after: retry_after)
        end

        errors = body[:errors].is_a?(Array) ? body[:errors].grep(Hash).map { |entry| field_error(entry) } : []
        new(
          body[:message],
          name: body[:name].is_a?(String) ? body[:name] : fallback,
          status_code: body[:statusCode].is_a?(Integer) ? body[:statusCode] : status,
          errors: errors.empty? ? nil : errors,
          retry_after: retry_after
        )
      end

      def self.field_error(entry)
        error = {
          field: entry[:field].is_a?(String) ? entry[:field] : "",
          message: entry[:message].is_a?(String) ? entry[:message] : ""
        }
        error[:i18nTranslationKey] = entry[:i18nTranslationKey] if entry[:i18nTranslationKey].is_a?(String)
        error
      end
      private_class_method :field_error
    end
  end
end
