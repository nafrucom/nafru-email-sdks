use crate::dev_outbox::{DevEmail, write_dev_email};
use crate::error::Result;
use crate::http::{Http, Req, seg};
use crate::types::*;
use std::path::PathBuf;

macro_rules! resource {
    ($($(#[$meta:meta])* $name:ident),+ $(,)?) => {
        $($(#[$meta])* #[derive(Clone)]
        pub struct $name {
            http: Http,
        })+
    };
}

resource!(
    Domains,
    ContactProperties,
    ContactSegments,
    ContactTopics,
    Segments,
    Topics,
    Broadcasts,
    Templates,
    /// Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı `brand` alanıyla devralır.
    BrandResource,
    Webhooks,
    ApiKeys,
    /// Otomasyonları tetikleyen özel olay API'si.
    Events,
);

#[derive(Clone)]
pub struct Emails {
    http: Http,
    dev_outbox: Option<PathBuf>,
}

impl Emails {
    pub(crate) fn new(http: Http, dev_outbox: Option<PathBuf>) -> Self {
        Self { http, dev_outbox }
    }

    /// `POST /emails`. `scheduled_at` verilirse zamanlanır; `idempotency_key` ile yineleme güvenlidir.
    pub async fn send(
        &self,
        input: &SendEmailInput,
        options: SendEmailOptions,
    ) -> Result<SendEmailResponse> {
        if let Some(dir) = &self.dev_outbox {
            return write_dev_email(dir, &DevEmail::from(input));
        }
        let mut req = Req::new("POST", "/emails".into()).body(input);
        req.idempotency_key = options.idempotency_key.as_deref();
        self.http.request(req).await
    }

    /// `POST /emails/batch`: en çok 100 e-posta; ek ve şablon desteklenmez.
    pub async fn batch(
        &self,
        input: &[BatchEmailItem],
        options: SendEmailOptions,
    ) -> Result<BatchEmailResponse> {
        if let Some(dir) = &self.dev_outbox {
            let data = input
                .iter()
                .map(|item| write_dev_email(dir, &DevEmail::from(item)))
                .collect::<Result<_>>()?;
            return Ok(BatchEmailResponse { data });
        }
        let mut req = Req::new("POST", "/emails/batch".into()).body(&input);
        req.idempotency_key = options.idempotency_key.as_deref();
        self.http.request(req).await
    }

    pub async fn get(&self, id: &str) -> Result<Email> {
        self.http
            .request(Req::new("GET", format!("/emails/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListEmailsQuery) -> Result<ListResponse<EmailListItem>> {
        self.http
            .request(Req::new("GET", "/emails".into()).query(&query))
            .await
    }

    /// Zamanlanmış e-postanın gönderim anını değiştirir.
    pub async fn update(&self, id: &str, input: &UpdateEmailInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/emails/{}", seg(id))).body(input))
            .await
    }

    /// Zamanlanmış e-postayı iptal eder.
    pub async fn cancel(&self, id: &str) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", format!("/emails/{}/cancel", seg(id))))
            .await
    }
}

impl Domains {
    pub async fn create(&self, input: &CreateDomainInput) -> Result<DomainDetail> {
        self.http
            .request(Req::new("POST", "/domains".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<DomainDetail> {
        self.http
            .request(Req::new("GET", format!("/domains/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<Domain>> {
        self.http
            .request(Req::new("GET", "/domains".into()).query(&query))
            .await
    }

    pub async fn update(&self, id: &str, input: &UpdateDomainInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/domains/{}", seg(id))).body(input))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/domains/{}", seg(id))))
            .await
    }

    /// DNS kayıtlarını denetletir; sonuç `get` ile okunur.
    pub async fn verify(&self, id: &str) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", format!("/domains/{}/verify", seg(id))))
            .await
    }
}

/// Kişi uçlarında `id` yerine e-posta adresi de verilebilir.
#[derive(Clone)]
pub struct Contacts {
    http: Http,
    pub segments: ContactSegments,
    pub topics: ContactTopics,
}

impl Contacts {
    pub async fn create(&self, input: &CreateContactInput) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", "/contacts".into()).body(input))
            .await
    }

    pub async fn get(&self, id_or_email: &str) -> Result<ContactDetail> {
        self.http
            .request(Req::new("GET", format!("/contacts/{}", seg(id_or_email))))
            .await
    }

    pub async fn list(&self, query: ListContactsQuery) -> Result<ListResponse<Contact>> {
        self.http
            .request(Req::new("GET", "/contacts".into()).query(&query))
            .await
    }

    pub async fn update(&self, id_or_email: &str, input: &UpdateContactInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/contacts/{}", seg(id_or_email))).body(input))
            .await
    }

    pub async fn remove(&self, id_or_email: &str) -> Result<DeletedContact> {
        self.http
            .request(Req::new(
                "DELETE",
                format!("/contacts/{}", seg(id_or_email)),
            ))
            .await
    }
}

impl ContactSegments {
    pub async fn list(&self, id_or_email: &str, query: ListQuery) -> Result<ListResponse<Segment>> {
        self.http
            .request(
                Req::new("GET", format!("/contacts/{}/segments", seg(id_or_email))).query(&query),
            )
            .await
    }

    /// Kişiyi statik segmente ekler (dinamik segmentte 422).
    pub async fn add(&self, id_or_email: &str, segment_id: &str) -> Result<IdRef> {
        let path = format!(
            "/contacts/{}/segments/{}",
            seg(id_or_email),
            seg(segment_id)
        );
        self.http.request(Req::new("POST", path)).await
    }

    pub async fn remove(&self, id_or_email: &str, segment_id: &str) -> Result<DeletedLink> {
        let path = format!(
            "/contacts/{}/segments/{}",
            seg(id_or_email),
            seg(segment_id)
        );
        self.http.request(Req::new("DELETE", path)).await
    }
}

impl ContactTopics {
    pub async fn list(
        &self,
        id_or_email: &str,
        query: ListQuery,
    ) -> Result<ListResponse<ContactTopic>> {
        self.http
            .request(
                Req::new("GET", format!("/contacts/{}/topics", seg(id_or_email))).query(&query),
            )
            .await
    }

    pub async fn update(
        &self,
        id_or_email: &str,
        input: &UpdateContactTopicsInput,
    ) -> Result<IdRef> {
        // Sunucu gövdede çıplak dizi bekler.
        let req =
            Req::new("PATCH", format!("/contacts/{}/topics", seg(id_or_email))).body(&input.topics);
        self.http.request(req).await
    }
}

impl ContactProperties {
    pub async fn create(&self, input: &CreateContactPropertyInput) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", "/contact-properties".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<ContactPropertyDetail> {
        self.http
            .request(Req::new("GET", format!("/contact-properties/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<ContactProperty>> {
        self.http
            .request(Req::new("GET", "/contact-properties".into()).query(&query))
            .await
    }

    pub async fn update(&self, id: &str, input: &UpdateContactPropertyInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/contact-properties/{}", seg(id))).body(input))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new(
                "DELETE",
                format!("/contact-properties/{}", seg(id)),
            ))
            .await
    }
}

impl Segments {
    pub async fn create(&self, input: &CreateSegmentInput) -> Result<SegmentRef> {
        self.http
            .request(Req::new("POST", "/segments".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<SegmentDetail> {
        self.http
            .request(Req::new("GET", format!("/segments/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<Segment>> {
        self.http
            .request(Req::new("GET", "/segments".into()).query(&query))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/segments/{}", seg(id))))
            .await
    }

    /// Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
    pub async fn contacts(
        &self,
        id: &str,
        query: SegmentContactsQuery,
    ) -> Result<ListResponse<Contact>> {
        self.http
            .request(Req::new("GET", format!("/segments/{}/contacts", seg(id))).query(&query))
            .await
    }
}

impl Topics {
    pub async fn create(&self, input: &CreateTopicInput) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", "/topics".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<TopicDetail> {
        self.http
            .request(Req::new("GET", format!("/topics/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<Topic>> {
        self.http
            .request(Req::new("GET", "/topics".into()).query(&query))
            .await
    }

    pub async fn update(&self, id: &str, input: &UpdateTopicInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/topics/{}", seg(id))).body(input))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/topics/{}", seg(id))))
            .await
    }
}

impl Broadcasts {
    /// Taslak oluşturur; `send: Some(true)` ile aynı istekte gönderir.
    pub async fn create(&self, input: &CreateBroadcastInput) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", "/broadcasts".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<Broadcast> {
        self.http
            .request(Req::new("GET", format!("/broadcasts/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<BroadcastListItem>> {
        self.http
            .request(Req::new("GET", "/broadcasts".into()).query(&query))
            .await
    }

    /// Yalnız taslakta (aksi 409).
    pub async fn update(&self, id: &str, input: &UpdateBroadcastInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/broadcasts/{}", seg(id))).body(input))
            .await
    }

    /// Yalnız taslakta (aksi 409).
    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/broadcasts/{}", seg(id))))
            .await
    }

    pub async fn send(&self, id: &str, input: &SendBroadcastInput) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", format!("/broadcasts/{}/send", seg(id))).body(input))
            .await
    }

    pub async fn cancel(&self, id: &str) -> Result<IdRef> {
        self.http
            .request(Req::new("POST", format!("/broadcasts/{}/cancel", seg(id))))
            .await
    }
}

impl Templates {
    pub async fn create(&self, input: &CreateTemplateInput) -> Result<TemplateSaved> {
        self.http
            .request(Req::new("POST", "/templates".into()).body(input))
            .await
    }

    /// `id_or_alias`: kimlik ya da takma ad.
    pub async fn get(&self, id_or_alias: &str) -> Result<Template> {
        self.http
            .request(Req::new("GET", format!("/templates/{}", seg(id_or_alias))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<TemplateListItem>> {
        self.http
            .request(Req::new("GET", "/templates".into()).query(&query))
            .await
    }

    /// Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.
    pub async fn update(
        &self,
        id_or_alias: &str,
        input: &UpdateTemplateInput,
    ) -> Result<TemplateSaved> {
        self.http
            .request(Req::new("PATCH", format!("/templates/{}", seg(id_or_alias))).body(input))
            .await
    }

    pub async fn remove(&self, id_or_alias: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new(
                "DELETE",
                format!("/templates/{}", seg(id_or_alias)),
            ))
            .await
    }

    pub async fn publish(&self, id_or_alias: &str) -> Result<TemplatePublished> {
        self.http
            .request(Req::new(
                "POST",
                format!("/templates/{}/publish", seg(id_or_alias)),
            ))
            .await
    }

    pub async fn duplicate(&self, id_or_alias: &str) -> Result<IdRef> {
        self.http
            .request(Req::new(
                "POST",
                format!("/templates/{}/duplicate", seg(id_or_alias)),
            ))
            .await
    }

    /// Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.
    pub async fn put_translation(
        &self,
        id_or_alias: &str,
        locale: &str,
        input: &PutTemplateTranslationInput,
    ) -> Result<TemplateTranslation> {
        let path = format!(
            "/templates/{}/translations/{}",
            seg(id_or_alias),
            seg(locale)
        );
        self.http.request(Req::new("PUT", path).body(input)).await
    }

    pub async fn remove_translation(
        &self,
        id_or_alias: &str,
        locale: &str,
    ) -> Result<TemplateTranslationDeleted> {
        let path = format!(
            "/templates/{}/translations/{}",
            seg(id_or_alias),
            seg(locale)
        );
        self.http.request(Req::new("DELETE", path)).await
    }
}

impl BrandResource {
    pub async fn get(&self) -> Result<Brand> {
        self.http.request(Req::new("GET", "/brand".into())).await
    }

    /// Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).
    pub async fn update(&self, input: &UpdateBrandInput) -> Result<Brand> {
        self.http
            .request(Req::new("PUT", "/brand".into()).body(input))
            .await
    }
}

impl Webhooks {
    /// Yanıttaki `signing_secret` ile `verify_webhook` kullanılır.
    pub async fn create(&self, input: &CreateWebhookInput) -> Result<CreatedWebhook> {
        self.http
            .request(Req::new("POST", "/webhooks".into()).body(input))
            .await
    }

    pub async fn get(&self, id: &str) -> Result<WebhookDetail> {
        self.http
            .request(Req::new("GET", format!("/webhooks/{}", seg(id))))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<Webhook>> {
        self.http
            .request(Req::new("GET", "/webhooks".into()).query(&query))
            .await
    }

    pub async fn update(&self, id: &str, input: &UpdateWebhookInput) -> Result<IdRef> {
        self.http
            .request(Req::new("PATCH", format!("/webhooks/{}", seg(id))).body(input))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/webhooks/{}", seg(id))))
            .await
    }
}

impl ApiKeys {
    pub async fn create(&self, input: &CreateApiKeyInput) -> Result<CreatedApiKey> {
        self.http
            .request(Req::new("POST", "/api-keys".into()).body(input))
            .await
    }

    pub async fn list(&self, query: ListQuery) -> Result<ListResponse<ApiKey>> {
        self.http
            .request(Req::new("GET", "/api-keys".into()).query(&query))
            .await
    }

    pub async fn remove(&self, id: &str) -> Result<DeletedResponse> {
        self.http
            .request(Req::new("DELETE", format!("/api-keys/{}", seg(id))))
            .await
    }
}

impl Events {
    pub async fn send(
        &self,
        input: &SendEventInput,
        options: SendEventOptions,
    ) -> Result<EventAccepted> {
        let mut req = Req::new("POST", "/events".into()).body(input);
        req.idempotency_key = options.idempotency_key.as_deref();
        self.http.request(req).await
    }

    /// En çok 100 olay; biri geçersizse tüm istek 422.
    pub async fn batch(
        &self,
        input: &[SendEventInput],
        options: SendEventOptions,
    ) -> Result<EventBatchResponse> {
        let mut req = Req::new("POST", "/events/batch".into()).body(&input);
        req.idempotency_key = options.idempotency_key.as_deref();
        self.http.request(req).await
    }

    pub async fn list(&self, query: ListEventsQuery) -> Result<ListResponse<EventItem>> {
        self.http
            .request(Req::new("GET", "/events".into()).query(&query))
            .await
    }
}

/// API anahtarlı istemci (`NafruEmail::new`). Tüm kaynaklar tek HTTP katmanını paylaşır; `Clone` ucuzdur.
#[derive(Clone)]
pub struct NafruEmail {
    pub emails: Emails,
    pub domains: Domains,
    pub contacts: Contacts,
    pub contact_properties: ContactProperties,
    pub segments: Segments,
    pub topics: Topics,
    pub broadcasts: Broadcasts,
    pub templates: Templates,
    pub brand: BrandResource,
    pub webhooks: Webhooks,
    pub api_keys: ApiKeys,
    pub events: Events,
}

pub(crate) fn build(http: Http, dev_outbox: Option<PathBuf>) -> NafruEmail {
    let h = || http.clone();
    NafruEmail {
        emails: Emails::new(h(), dev_outbox),
        domains: Domains { http: h() },
        contacts: Contacts {
            http: h(),
            segments: ContactSegments { http: h() },
            topics: ContactTopics { http: h() },
        },
        contact_properties: ContactProperties { http: h() },
        segments: Segments { http: h() },
        topics: Topics { http: h() },
        broadcasts: Broadcasts { http: h() },
        templates: Templates { http: h() },
        brand: BrandResource { http: h() },
        webhooks: Webhooks { http: h() },
        api_keys: ApiKeys { http: h() },
        events: Events { http: h() },
    }
}

impl std::fmt::Debug for NafruEmail {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("NafruEmail")
            .field("http", &self.emails.http)
            .finish()
    }
}
