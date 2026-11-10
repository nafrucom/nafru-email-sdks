from typing import List, Optional, cast

from ._http import Http, seg
from .dev_outbox import write_dev_email
from .types import (
    BatchEmailItem,
    BatchEmailResponse,
    Brand,
    Broadcast,
    BroadcastRef,
    ContactDetail,
    ContactPropertyDetail,
    ContactPropertyRef,
    ContactRef,
    CreateApiKeyInput,
    CreateBroadcastInput,
    CreateContactInput,
    CreateContactPropertyInput,
    CreatedApiKey,
    CreateDomainInput,
    CreatedWebhook,
    CreateSegmentInput,
    CreateTemplateInput,
    CreateTopicInput,
    CreateWebhookInput,
    DeletedContact,
    DeletedResponse,
    DomainDetail,
    DomainRef,
    Email,
    EmailRef,
    EventAccepted,
    EventBatchResponse,
    IdRef,
    ListResponse,
    PutTemplateTranslationInput,
    SegmentDetail,
    SegmentMembershipRemoved,
    SegmentRef,
    SendBroadcastInput,
    SendEmailInput,
    SendEmailResponse,
    SendEventInput,
    Template,
    TemplatePublished,
    TemplateRef,
    TemplateSaved,
    TemplateTranslation,
    TemplateTranslationDeleted,
    TopicDetail,
    TopicRef,
    UpdateBroadcastInput,
    UpdateBrandInput,
    UpdateContactInput,
    UpdateContactPropertyInput,
    UpdateContactTopicsInput,
    UpdateDomainInput,
    UpdateEmailInput,
    UpdateTemplateInput,
    UpdateTopicInput,
    UpdateWebhookInput,
    WebhookDetail,
    WebhookRef,
)

# Her `list` yöntemi `ListResponse` döner; `data` öğe türü yöntem belgesinde yazılıdır (genel TypedDict Python 3.11 ister).


def _page(limit: Optional[int], after: Optional[str], before: Optional[str]) -> dict:
    return {"limit": limit, "after": after, "before": before}


class _Resource:
    def __init__(self, http: Http) -> None:
        self._http = http


class Emails(_Resource):
    def __init__(self, http: Http, dev_outbox: Optional[str] = None) -> None:
        super().__init__(http)
        self._dev_outbox = dev_outbox

    def send(self, params: SendEmailInput, *, idempotency_key: Optional[str] = None) -> SendEmailResponse:
        """`POST /emails`. `scheduled_at` verilirse zamanlanır; `idempotency_key` ile yineleme güvenlidir."""
        if self._dev_outbox:
            return write_dev_email(self._dev_outbox, params)
        return cast(
            SendEmailResponse,
            self._http.request("POST", "/emails", body=params, idempotency_key=idempotency_key),
        )

    def batch(self, params: List[BatchEmailItem], *, idempotency_key: Optional[str] = None) -> BatchEmailResponse:
        """`POST /emails/batch`: en çok 100 e-posta; ek ve şablon desteklenmez."""
        if self._dev_outbox:
            return {"data": [write_dev_email(self._dev_outbox, item) for item in params]}
        return cast(
            BatchEmailResponse,
            self._http.request("POST", "/emails/batch", body=params, idempotency_key=idempotency_key),
        )

    def get(self, id: str) -> Email:
        return cast(Email, self._http.request("GET", f"/emails/{seg(id)}"))

    def list(
        self,
        *,
        limit: Optional[int] = None,
        after: Optional[str] = None,
        before: Optional[str] = None,
        status: Optional[str] = None,
    ) -> ListResponse:
        """Öğeler: `EmailListItem`."""
        query = {**_page(limit, after, before), "status": status}
        return cast(ListResponse, self._http.request("GET", "/emails", query=query))

    def update(self, id: str, params: UpdateEmailInput) -> EmailRef:
        """Zamanlanmış e-postanın gönderim anını değiştirir."""
        return cast(EmailRef, self._http.request("PATCH", f"/emails/{seg(id)}", body=params))

    def cancel(self, id: str) -> EmailRef:
        """Zamanlanmış e-postayı iptal eder."""
        return cast(EmailRef, self._http.request("POST", f"/emails/{seg(id)}/cancel"))


class Domains(_Resource):
    def create(self, params: CreateDomainInput) -> DomainDetail:
        return cast(DomainDetail, self._http.request("POST", "/domains", body=params))

    def get(self, id: str) -> DomainDetail:
        return cast(DomainDetail, self._http.request("GET", f"/domains/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `Domain`."""
        return cast(ListResponse, self._http.request("GET", "/domains", query=_page(limit, after, before)))

    def update(self, id: str, params: UpdateDomainInput) -> DomainRef:
        return cast(DomainRef, self._http.request("PATCH", f"/domains/{seg(id)}", body=params))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/domains/{seg(id)}"))

    def verify(self, id: str) -> DomainRef:
        """DNS kayıtlarını denetletir; sonuç `get` ile okunur."""
        return cast(DomainRef, self._http.request("POST", f"/domains/{seg(id)}/verify"))


class ContactSegments(_Resource):
    def list(
        self, id_or_email: str, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `Segment`."""
        path = f"/contacts/{seg(id_or_email)}/segments"
        return cast(ListResponse, self._http.request("GET", path, query=_page(limit, after, before)))

    def add(self, id_or_email: str, segment_id: str) -> IdRef:
        """Kişiyi statik segmente ekler (dinamik segmentte 422)."""
        return cast(IdRef, self._http.request("POST", f"/contacts/{seg(id_or_email)}/segments/{seg(segment_id)}"))

    def remove(self, id_or_email: str, segment_id: str) -> SegmentMembershipRemoved:
        path = f"/contacts/{seg(id_or_email)}/segments/{seg(segment_id)}"
        return cast(SegmentMembershipRemoved, self._http.request("DELETE", path))


class ContactTopics(_Resource):
    def list(
        self, id_or_email: str, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `ContactTopic`."""
        path = f"/contacts/{seg(id_or_email)}/topics"
        return cast(ListResponse, self._http.request("GET", path, query=_page(limit, after, before)))

    def update(self, id_or_email: str, params: UpdateContactTopicsInput) -> ContactRef:
        # Sunucu gövdede çıplak dizi bekler.
        return cast(ContactRef, self._http.request("PATCH", f"/contacts/{seg(id_or_email)}/topics", body=params["topics"]))


class Contacts(_Resource):
    """Kişi uçlarında `id` yerine e-posta adresi de verilebilir."""

    def __init__(self, http: Http) -> None:
        super().__init__(http)
        self.segments = ContactSegments(http)
        self.topics = ContactTopics(http)

    def create(self, params: CreateContactInput) -> ContactRef:
        return cast(ContactRef, self._http.request("POST", "/contacts", body=params))

    def get(self, id_or_email: str) -> ContactDetail:
        return cast(ContactDetail, self._http.request("GET", f"/contacts/{seg(id_or_email)}"))

    def list(
        self,
        *,
        limit: Optional[int] = None,
        after: Optional[str] = None,
        before: Optional[str] = None,
        search: Optional[str] = None,
    ) -> ListResponse:
        """Öğeler: `Contact`. `search` e-posta, ad ya da soyad içinde arar."""
        query = {**_page(limit, after, before), "search": search}
        return cast(ListResponse, self._http.request("GET", "/contacts", query=query))

    def update(self, id_or_email: str, params: UpdateContactInput) -> ContactRef:
        return cast(ContactRef, self._http.request("PATCH", f"/contacts/{seg(id_or_email)}", body=params))

    def remove(self, id_or_email: str) -> DeletedContact:
        return cast(DeletedContact, self._http.request("DELETE", f"/contacts/{seg(id_or_email)}"))


class ContactProperties(_Resource):
    def create(self, params: CreateContactPropertyInput) -> ContactPropertyRef:
        return cast(ContactPropertyRef, self._http.request("POST", "/contact-properties", body=params))

    def get(self, id: str) -> ContactPropertyDetail:
        return cast(ContactPropertyDetail, self._http.request("GET", f"/contact-properties/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `ContactProperty`."""
        return cast(ListResponse, self._http.request("GET", "/contact-properties", query=_page(limit, after, before)))

    def update(self, id: str, params: UpdateContactPropertyInput) -> ContactPropertyRef:
        return cast(ContactPropertyRef, self._http.request("PATCH", f"/contact-properties/{seg(id)}", body=params))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/contact-properties/{seg(id)}"))


class Segments(_Resource):
    def create(self, params: CreateSegmentInput) -> SegmentRef:
        return cast(SegmentRef, self._http.request("POST", "/segments", body=params))

    def get(self, id: str) -> SegmentDetail:
        return cast(SegmentDetail, self._http.request("GET", f"/segments/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `Segment`."""
        return cast(ListResponse, self._http.request("GET", "/segments", query=_page(limit, after, before)))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/segments/{seg(id)}"))

    def contacts(self, id: str, *, limit: Optional[int] = None, after: Optional[str] = None) -> ListResponse:
        """Segmentin kişileri (`Contact`); sayfalama kimlik sırasıyla, yalnız `after`."""
        query = {"limit": limit, "after": after}
        return cast(ListResponse, self._http.request("GET", f"/segments/{seg(id)}/contacts", query=query))


class Topics(_Resource):
    def create(self, params: CreateTopicInput) -> TopicRef:
        return cast(TopicRef, self._http.request("POST", "/topics", body=params))

    def get(self, id: str) -> TopicDetail:
        return cast(TopicDetail, self._http.request("GET", f"/topics/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `Topic`."""
        return cast(ListResponse, self._http.request("GET", "/topics", query=_page(limit, after, before)))

    def update(self, id: str, params: UpdateTopicInput) -> TopicRef:
        return cast(TopicRef, self._http.request("PATCH", f"/topics/{seg(id)}", body=params))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/topics/{seg(id)}"))


class Broadcasts(_Resource):
    def create(self, params: CreateBroadcastInput) -> BroadcastRef:
        """Taslak oluşturur; `send: True` ile aynı istekte gönderir."""
        return cast(BroadcastRef, self._http.request("POST", "/broadcasts", body=params))

    def get(self, id: str) -> Broadcast:
        return cast(Broadcast, self._http.request("GET", f"/broadcasts/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `BroadcastListItem`."""
        return cast(ListResponse, self._http.request("GET", "/broadcasts", query=_page(limit, after, before)))

    def update(self, id: str, params: UpdateBroadcastInput) -> BroadcastRef:
        """Yalnız taslakta (aksi 409)."""
        return cast(BroadcastRef, self._http.request("PATCH", f"/broadcasts/{seg(id)}", body=params))

    def remove(self, id: str) -> DeletedResponse:
        """Yalnız taslakta (aksi 409)."""
        return cast(DeletedResponse, self._http.request("DELETE", f"/broadcasts/{seg(id)}"))

    def send(self, id: str, params: Optional[SendBroadcastInput] = None) -> BroadcastRef:
        body = params if params is not None else {}
        return cast(BroadcastRef, self._http.request("POST", f"/broadcasts/{seg(id)}/send", body=body))

    def cancel(self, id: str) -> BroadcastRef:
        return cast(BroadcastRef, self._http.request("POST", f"/broadcasts/{seg(id)}/cancel"))


class Templates(_Resource):
    """`id_or_alias`: kimlik ya da takma ad."""

    def create(self, params: CreateTemplateInput) -> TemplateSaved:
        return cast(TemplateSaved, self._http.request("POST", "/templates", body=params))

    def get(self, id_or_alias: str) -> Template:
        return cast(Template, self._http.request("GET", f"/templates/{seg(id_or_alias)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `TemplateListItem`."""
        return cast(ListResponse, self._http.request("GET", "/templates", query=_page(limit, after, before)))

    def update(self, id_or_alias: str, params: UpdateTemplateInput) -> TemplateSaved:
        """Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır."""
        return cast(TemplateSaved, self._http.request("PATCH", f"/templates/{seg(id_or_alias)}", body=params))

    def remove(self, id_or_alias: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/templates/{seg(id_or_alias)}"))

    def publish(self, id_or_alias: str) -> TemplatePublished:
        return cast(TemplatePublished, self._http.request("POST", f"/templates/{seg(id_or_alias)}/publish"))

    def duplicate(self, id_or_alias: str) -> TemplateRef:
        return cast(TemplateRef, self._http.request("POST", f"/templates/{seg(id_or_alias)}/duplicate"))

    def put_translation(
        self, id_or_alias: str, locale: str, params: PutTemplateTranslationInput
    ) -> TemplateTranslation:
        """Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır."""
        path = f"/templates/{seg(id_or_alias)}/translations/{seg(locale)}"
        return cast(TemplateTranslation, self._http.request("PUT", path, body=params))

    def remove_translation(self, id_or_alias: str, locale: str) -> TemplateTranslationDeleted:
        path = f"/templates/{seg(id_or_alias)}/translations/{seg(locale)}"
        return cast(TemplateTranslationDeleted, self._http.request("DELETE", path))


class BrandResource(_Resource):
    """Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı `brand` alanıyla devralır."""

    def get(self) -> Brand:
        return cast(Brand, self._http.request("GET", "/brand"))

    def update(self, params: UpdateBrandInput) -> Brand:
        """Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur)."""
        return cast(Brand, self._http.request("PUT", "/brand", body=params))


class Webhooks(_Resource):
    def create(self, params: CreateWebhookInput) -> CreatedWebhook:
        """Yanıttaki `signing_secret` ile `verify_webhook` kullanılır."""
        return cast(CreatedWebhook, self._http.request("POST", "/webhooks", body=params))

    def get(self, id: str) -> WebhookDetail:
        return cast(WebhookDetail, self._http.request("GET", f"/webhooks/{seg(id)}"))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `Webhook`."""
        return cast(ListResponse, self._http.request("GET", "/webhooks", query=_page(limit, after, before)))

    def update(self, id: str, params: UpdateWebhookInput) -> WebhookRef:
        return cast(WebhookRef, self._http.request("PATCH", f"/webhooks/{seg(id)}", body=params))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/webhooks/{seg(id)}"))


class ApiKeys(_Resource):
    def create(self, params: CreateApiKeyInput) -> CreatedApiKey:
        return cast(CreatedApiKey, self._http.request("POST", "/api-keys", body=params))

    def list(
        self, *, limit: Optional[int] = None, after: Optional[str] = None, before: Optional[str] = None
    ) -> ListResponse:
        """Öğeler: `ApiKey`."""
        return cast(ListResponse, self._http.request("GET", "/api-keys", query=_page(limit, after, before)))

    def remove(self, id: str) -> DeletedResponse:
        return cast(DeletedResponse, self._http.request("DELETE", f"/api-keys/{seg(id)}"))


class Events(_Resource):
    """Otomasyonları tetikleyen özel olay API'si. `idempotency_key`: aynı anahtarla yinelenen istek olayı bir kez işler."""

    def send(self, params: SendEventInput, *, idempotency_key: Optional[str] = None) -> EventAccepted:
        return cast(EventAccepted, self._http.request("POST", "/events", body=params, idempotency_key=idempotency_key))

    def batch(self, params: List[SendEventInput], *, idempotency_key: Optional[str] = None) -> EventBatchResponse:
        """En çok 100 olay; biri geçersizse tüm istek 422."""
        return cast(
            EventBatchResponse,
            self._http.request("POST", "/events/batch", body=params, idempotency_key=idempotency_key),
        )

    def list(
        self,
        *,
        limit: Optional[int] = None,
        after: Optional[str] = None,
        before: Optional[str] = None,
        name: Optional[str] = None,
        contact_id: Optional[str] = None,
        email: Optional[str] = None,
    ) -> ListResponse:
        """Öğeler: `EventItem`. `email`, `contact_id` ile birlikte verilmez."""
        query = {**_page(limit, after, before), "name": name, "contact_id": contact_id, "email": email}
        return cast(ListResponse, self._http.request("GET", "/events", query=query))

