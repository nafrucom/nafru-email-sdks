# frozen_string_literal: true

module Nafru
  module Email
    # Kaynaklar `Http#request` ile konuşur. Girdi ve yanıt alanları API'deki gibi snake_case'tir; şekiller `sig/nafru_email.rbs`'te.
    module Resources
      # Ortak taban: `http` `request(method, path, query:, body:, idempotency_key:)` yanıtlayan nesnedir.
      class Base
        def initialize(http) = @http = http

        private

        def req(method, path, **options) = @http.request(method, path, **options)

        def seg(value) = Http.seg(value)
      end

      class Emails < Base
        def initialize(http, dev_outbox = false)
          super(http)
          @dev_outbox = dev_outbox
        end

        # `POST /emails`. `scheduled_at` verilirse zamanlanır; `idempotency_key` ile yineleme güvenlidir.
        def send(input, idempotency_key: nil)
          return DevOutbox.write(@dev_outbox, input) if @dev_outbox

          req("POST", "/emails", body: input, idempotency_key: idempotency_key)
        end

        # `POST /emails/batch`: en çok 100 e-posta; ek ve şablon desteklenmez.
        def batch(input, idempotency_key: nil)
          return { data: input.map { |item| DevOutbox.write(@dev_outbox, item) } } if @dev_outbox

          req("POST", "/emails/batch", body: input, idempotency_key: idempotency_key)
        end

        def get(id) = req("GET", "/emails/#{seg(id)}")
        def list(query = {}) = req("GET", "/emails", query: query)
        # Zamanlanmış e-postanın gönderim anını değiştirir.
        def update(id, input) = req("PATCH", "/emails/#{seg(id)}", body: input)
        # Zamanlanmış e-postayı iptal eder.
        def cancel(id) = req("POST", "/emails/#{seg(id)}/cancel")
      end

      class Domains < Base
        def create(input) = req("POST", "/domains", body: input)
        def get(id) = req("GET", "/domains/#{seg(id)}")
        def list(query = {}) = req("GET", "/domains", query: query)
        def update(id, input) = req("PATCH", "/domains/#{seg(id)}", body: input)
        def remove(id) = req("DELETE", "/domains/#{seg(id)}")
        # DNS kayıtlarını denetletir; sonuç `get` ile okunur.
        def verify(id) = req("POST", "/domains/#{seg(id)}/verify")
      end

      # Kişi uçlarında `id` yerine e-posta adresi de verilebilir.
      class Contacts < Base
        attr_reader :segments, :topics

        def initialize(http)
          super
          @segments = ContactSegments.new(http)
          @topics = ContactTopics.new(http)
        end

        def create(input) = req("POST", "/contacts", body: input)
        def get(id_or_email) = req("GET", "/contacts/#{seg(id_or_email)}")
        def list(query = {}) = req("GET", "/contacts", query: query)
        def update(id_or_email, input) = req("PATCH", "/contacts/#{seg(id_or_email)}", body: input)
        def remove(id_or_email) = req("DELETE", "/contacts/#{seg(id_or_email)}")
      end

      class ContactSegments < Base
        def list(id_or_email, query = {}) = req("GET", "/contacts/#{seg(id_or_email)}/segments", query: query)
        # Kişiyi statik segmente ekler (dinamik segmentte 422).
        def add(id_or_email, segment_id) = req("POST", "/contacts/#{seg(id_or_email)}/segments/#{seg(segment_id)}")
        def remove(id_or_email, segment_id) = req("DELETE", "/contacts/#{seg(id_or_email)}/segments/#{seg(segment_id)}")
      end

      class ContactTopics < Base
        def list(id_or_email, query = {}) = req("GET", "/contacts/#{seg(id_or_email)}/topics", query: query)

        # `input`: `{ topics: [{ id:, subscription: "opt_in" | "opt_out" }] }`. Sunucu gövdede çıplak dizi bekler.
        def update(id_or_email, input)
          req("PATCH", "/contacts/#{seg(id_or_email)}/topics", body: input[:topics] || input["topics"])
        end
      end

      class ContactProperties < Base
        def create(input) = req("POST", "/contact-properties", body: input)
        def get(id) = req("GET", "/contact-properties/#{seg(id)}")
        def list(query = {}) = req("GET", "/contact-properties", query: query)
        def update(id, input) = req("PATCH", "/contact-properties/#{seg(id)}", body: input)
        def remove(id) = req("DELETE", "/contact-properties/#{seg(id)}")
      end

      class Segments < Base
        def create(input) = req("POST", "/segments", body: input)
        def get(id) = req("GET", "/segments/#{seg(id)}")
        def list(query = {}) = req("GET", "/segments", query: query)
        def remove(id) = req("DELETE", "/segments/#{seg(id)}")
        # Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
        def contacts(id, query = {}) = req("GET", "/segments/#{seg(id)}/contacts", query: query)
      end

      class Topics < Base
        def create(input) = req("POST", "/topics", body: input)
        def get(id) = req("GET", "/topics/#{seg(id)}")
        def list(query = {}) = req("GET", "/topics", query: query)
        def update(id, input) = req("PATCH", "/topics/#{seg(id)}", body: input)
        def remove(id) = req("DELETE", "/topics/#{seg(id)}")
      end

      class Broadcasts < Base
        # Taslak oluşturur; `send: true` ile aynı istekte gönderir.
        def create(input) = req("POST", "/broadcasts", body: input)
        def get(id) = req("GET", "/broadcasts/#{seg(id)}")
        def list(query = {}) = req("GET", "/broadcasts", query: query)
        # Yalnız taslakta (aksi 409).
        def update(id, input) = req("PATCH", "/broadcasts/#{seg(id)}", body: input)
        # Yalnız taslakta (aksi 409).
        def remove(id) = req("DELETE", "/broadcasts/#{seg(id)}")
        def send(id, input = {}) = req("POST", "/broadcasts/#{seg(id)}/send", body: input)
        def cancel(id) = req("POST", "/broadcasts/#{seg(id)}/cancel")
      end

      # `id_or_alias`: kimlik ya da takma ad.
      class Templates < Base
        def create(input) = req("POST", "/templates", body: input)
        def get(id_or_alias) = req("GET", "/templates/#{seg(id_or_alias)}")
        def list(query = {}) = req("GET", "/templates", query: query)
        # Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.
        def update(id_or_alias, input) = req("PATCH", "/templates/#{seg(id_or_alias)}", body: input)
        def remove(id_or_alias) = req("DELETE", "/templates/#{seg(id_or_alias)}")
        def publish(id_or_alias) = req("POST", "/templates/#{seg(id_or_alias)}/publish")
        def duplicate(id_or_alias) = req("POST", "/templates/#{seg(id_or_alias)}/duplicate")

        # Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.
        def put_translation(id_or_alias, locale, input)
          req("PUT", "/templates/#{seg(id_or_alias)}/translations/#{seg(locale)}", body: input)
        end

        def remove_translation(id_or_alias, locale)
          req("DELETE", "/templates/#{seg(id_or_alias)}/translations/#{seg(locale)}")
        end
      end

      # Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı `brand` alanıyla devralır.
      class Brand < Base
        def get = req("GET", "/brand")
        # Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).
        def update(input) = req("PUT", "/brand", body: input)
      end

      class Webhooks < Base
        # Yanıttaki `signing_secret` ile `Webhook.verify` kullanılır.
        def create(input) = req("POST", "/webhooks", body: input)
        def get(id) = req("GET", "/webhooks/#{seg(id)}")
        def list(query = {}) = req("GET", "/webhooks", query: query)
        def update(id, input) = req("PATCH", "/webhooks/#{seg(id)}", body: input)
        def remove(id) = req("DELETE", "/webhooks/#{seg(id)}")
      end

      class ApiKeys < Base
        def create(input) = req("POST", "/api-keys", body: input)
        def list(query = {}) = req("GET", "/api-keys", query: query)
        def remove(id) = req("DELETE", "/api-keys/#{seg(id)}")
      end

      # Otomasyonları tetikleyen özel olay API'si.
      class Events < Base
        def send(input, idempotency_key: nil) = req("POST", "/events", body: input, idempotency_key: idempotency_key)

        # En çok 100 olay; biri geçersizse tüm istek 422.
        def batch(input, idempotency_key: nil)
          req("POST", "/events/batch", body: input, idempotency_key: idempotency_key)
        end

        def list(query = {}) = req("GET", "/events", query: query)
      end
    end
  end
end
