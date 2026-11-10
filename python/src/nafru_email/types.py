"""İstek ve yanıt modelleri. Alan adları API'deki gibi `snake_case`'tir; dönüştürme katmanı yoktur.

Python 3.9 uyumu için zorunlu alanlar `_…Required` tabanında, isteğe bağlılar `total=False` alt sınıfta durur.
`from` Python'da ayrılmış kelime olduğundan onu taşıyan modeller işlevsel `TypedDict` söz dizimiyle yazılır.
"""

from typing import Any, Dict, List, Literal, Optional, TypedDict, Union

# --- ortak ---


class ListResponse(TypedDict):
    """Sunucunun `{ object: 'list', data, has_more }` liste zarfı."""

    object: Literal["list"]
    data: List[Any]
    has_more: bool


class DeletedResponse(TypedDict):
    object: str
    id: str
    deleted: Literal[True]


class Tag(TypedDict):
    name: str
    value: str


class NafruFieldError(TypedDict, total=False):
    field: str
    message: str
    i18nTranslationKey: str


StrOrList = Union[str, List[str]]

# --- emails ---

EmailStatus = str  # queued, scheduled, sent, delivered, delivery_delayed, bounced, complained, failed, canceled, …


class Attachment(TypedDict, total=False):
    #: Base64 metni. `path` ile birlikte verilmez.
    content: str
    #: Herkese açık https adresi. `content` ile birlikte verilmez.
    path: str
    filename: str
    content_type: str
    content_id: str


class EmailTemplateRef(TypedDict, total=False):
    id: str
    variables: Dict[str, Union[str, int, float]]


_EmailFields = TypedDict(
    "_EmailFields",
    {
        "from": str,
        "cc": StrOrList,
        "bcc": StrOrList,
        "reply_to": StrOrList,
        "subject": str,
        "headers": Dict[str, str],
        "tags": List[Tag],
        "scheduled_at": str,
        "html": str,
        "text": str,
    },
    total=False,
)


class _SendEmailRequired(TypedDict):
    to: StrOrList


class SendEmailInput(_SendEmailRequired, _EmailFields, total=False):
    """`from`: `Ad <adres@alan.com>`; şablonla gönderimde isteğe bağlı. `scheduled_at`: ISO 8601 ya da göreli (`in 1 hour`)."""

    attachments: List[Attachment]
    #: Şablonla gönderim: `html`/`text`/`attachments` ile birlikte verilmez.
    template: EmailTemplateRef


class BatchEmailItem(_SendEmailRequired, _EmailFields, total=False):
    """Toplu öğe: `from` ve `subject` zorunlu; ek ve şablon desteklenmez."""


class SendEmailResponse(TypedDict):
    id: str


class BatchEmailResponse(TypedDict):
    data: List[SendEmailResponse]


EmailListItem = TypedDict(
    "EmailListItem",
    {
        "id": str,
        "to": List[str],
        "from": str,
        "created_at": str,
        "subject": str,
        "bcc": Optional[List[str]],
        "cc": Optional[List[str]],
        "reply_to": Optional[List[str]],
        "last_event": EmailStatus,
        "scheduled_at": Optional[str],
        "message_id": Optional[str],
    },
)


class EmailEvent(TypedDict):
    id: str
    type: str
    created_at: str
    detail: Dict[str, Any]


class Email(EmailListItem):
    object: Literal["email"]
    html: Optional[str]
    text: Optional[str]
    tags: List[Tag]
    events: List[EmailEvent]


class EmailRef(TypedDict):
    object: Literal["email"]
    id: str


class UpdateEmailInput(TypedDict):
    scheduled_at: str


# --- domains ---

DomainStatus = Literal["not_started", "pending", "verified", "failed", "temporary_failure"]


class _DomainRecordRequired(TypedDict):
    record: Literal["SPF", "DKIM", "Tracking"]
    name: str
    type: Literal["MX", "TXT", "CNAME"]
    value: str
    ttl: Literal["Auto"]
    status: DomainStatus


class DomainRecord(_DomainRecordRequired, total=False):
    priority: int


class Domain(TypedDict):
    id: str
    name: str
    status: DomainStatus
    created_at: str
    region: str
    capabilities: Dict[str, str]
    open_tracking: bool
    click_tracking: bool
    tls: Literal["opportunistic", "enforced"]
    tracking_subdomain: Optional[str]


class DomainDetail(Domain):
    object: Literal["domain"]
    records: List[DomainRecord]


class _CreateDomainRequired(TypedDict):
    name: str


class CreateDomainInput(_CreateDomainRequired, total=False):
    region: str
    open_tracking: bool
    click_tracking: bool
    tls: Literal["opportunistic", "enforced"]
    #: Örn. `track` → `track.<alan-adı>`.
    tracking_subdomain: str


class UpdateDomainInput(TypedDict, total=False):
    open_tracking: bool
    click_tracking: bool
    tls: Literal["opportunistic", "enforced"]
    tracking_subdomain: Optional[str]


class DomainRef(TypedDict):
    object: Literal["domain"]
    id: str


# --- contacts ---

PropertyValue = Union[str, int, float, None]
TopicSubscription = Literal["opt_in", "opt_out"]


class Contact(TypedDict):
    id: str
    email: str
    first_name: Optional[str]
    last_name: Optional[str]
    unsubscribed: bool
    #: ISO 639-1 ana dil kodu; bölgeli kod (`pt-BR`) sunucuda ana dile indirgenir.
    locale: Optional[str]
    created_at: str


class ContactDetail(Contact):
    object: Literal["contact"]
    #: Yalnız değeri olan alanlar: `{ anahtar: { type, value } }`.
    properties: Dict[str, Dict[str, Any]]


class IdRef(TypedDict):
    id: str


class TopicSubscriptionInput(TypedDict):
    id: str
    subscription: TopicSubscription


class _CreateContactRequired(TypedDict):
    email: str


class CreateContactInput(_CreateContactRequired, total=False):
    first_name: Optional[str]
    last_name: Optional[str]
    unsubscribed: bool
    locale: Optional[str]
    properties: Dict[str, PropertyValue]
    segments: List[IdRef]
    topics: List[TopicSubscriptionInput]


class UpdateContactInput(TypedDict, total=False):
    first_name: Optional[str]
    last_name: Optional[str]
    unsubscribed: bool
    locale: Optional[str]
    properties: Dict[str, PropertyValue]


class ContactRef(TypedDict):
    object: Literal["contact"]
    id: str


class DeletedContact(TypedDict):
    object: Literal["contact"]
    contact: str
    deleted: Literal[True]


class ContactProperty(TypedDict):
    id: str
    key: str
    type: Literal["string", "number"]
    fallback_value: Union[str, int, float, None]
    created_at: str


class ContactPropertyDetail(ContactProperty):
    object: Literal["contact_property"]


class _CreateContactPropertyRequired(TypedDict):
    key: str
    type: Literal["string", "number"]


class CreateContactPropertyInput(_CreateContactPropertyRequired, total=False):
    fallback_value: Union[str, int, float, None]


class UpdateContactPropertyInput(TypedDict, total=False):
    fallback_value: Union[str, int, float, None]


class ContactPropertyRef(TypedDict):
    object: Literal["contact_property"]
    id: str


class SegmentMembershipRemoved(TypedDict):
    id: str
    deleted: Literal[True]


# --- segments ---

SegmentFilter = Dict[str, Any]


class Segment(TypedDict):
    id: str
    name: str
    created_at: str
    type: Literal["static", "dynamic"]
    filter: Optional[SegmentFilter]


class SegmentDetail(Segment):
    object: Literal["segment"]


class _CreateSegmentRequired(TypedDict):
    name: str


class CreateSegmentInput(_CreateSegmentRequired, total=False):
    #: Verilirse dinamik segment.
    filter: SegmentFilter


class SegmentRef(TypedDict):
    object: Literal["segment"]
    id: str
    name: str


# --- topics ---


class Topic(TypedDict):
    id: str
    name: str
    description: Optional[str]
    default_subscription: TopicSubscription
    visibility: Literal["public", "private"]
    double_opt_in: bool
    created_at: str


class TopicDetail(Topic):
    object: Literal["topic"]


class _CreateTopicRequired(TypedDict):
    name: str
    default_subscription: TopicSubscription


class CreateTopicInput(_CreateTopicRequired, total=False):
    description: Optional[str]
    visibility: Literal["public", "private"]
    double_opt_in: bool


class UpdateTopicInput(TypedDict, total=False):
    name: str
    description: Optional[str]
    visibility: Literal["public", "private"]
    double_opt_in: bool


class TopicRef(TypedDict):
    object: Literal["topic"]
    id: str


class ContactTopic(TypedDict):
    id: str
    name: str
    description: Optional[str]
    subscription: TopicSubscription
    #: `pending`: çift onay bekliyor (`subscription` bu durumda `opt_out` görünür).
    status: Literal["opt_in", "opt_out", "pending"]


class UpdateContactTopicsInput(TypedDict):
    topics: List[TopicSubscriptionInput]


# --- broadcasts ---

BroadcastStatus = Literal["draft", "scheduled", "sending", "sent", "paused", "canceled", "failed"]


class BroadcastListItem(TypedDict):
    id: str
    name: str
    segment_id: str
    audience_id: str
    subject: str
    status: BroadcastStatus
    created_at: str
    scheduled_at: Optional[str]
    sent_at: Optional[str]
    #: Tekrar kuralı (şablon kaydında); yoksa `None`.
    recurrence: Optional["BroadcastRecurrence"]
    #: Şablonun tetik durumu: `active`, `paused`; `None` = başlatılmadı.
    trigger_state: Optional[Literal["active", "paused"]]
    #: Sonraki zamanlı çalışma (ISO 8601); yoksa `None`.
    next_run_at: Optional[str]
    #: Çalışma örneğinde şablonun kimliği; yoksa `None`.
    parent_id: Optional[str]


# Tekrar kuralı; saat (`HH:MM`) çalışma alanının saat dilimindedir. `weekly.days`: 0 = pazar … 6 = cumartesi.
# `monthly.day`: 1–31 (ay kısaysa ayın son günü). `interval.every_days`: 1–365 gün.
# Yanıtlar düz `dict`'tir: bilinmeyen `type` değeri ayrıştırmayı bozmaz.
class WeeklyRecurrence(TypedDict):
    type: Literal["weekly"]
    days: List[int]
    time: str


class MonthlyRecurrence(TypedDict):
    type: Literal["monthly"]
    day: int
    time: str


class IntervalRecurrence(TypedDict):
    type: Literal["interval"]
    every_days: int
    time: str


BroadcastRecurrence = Union[WeeklyRecurrence, MonthlyRecurrence, IntervalRecurrence]


class ManualDataSource(TypedDict):
    type: Literal["manual"]


class _UrlDataSourceInputRequired(TypedDict):
    type: Literal["url"]
    url: str


class UrlDataSourceInput(_UrlDataSourceInputRequired, total=False):
    header_name: Optional[str]
    header_value: Optional[str]


class _WebhookDataSourceInputRequired(TypedDict):
    type: Literal["webhook"]


class WebhookDataSourceInput(_WebhookDataSourceInputRequired, total=False):
    regenerate_secret: bool


#: `{{{data.*}}}` değişkenlerinin kaynağı. `url`: gönderim anında `GET` (https, ≤ 256 KB JSON nesne, 10 sn). `webhook`: imzalı tetik ucu.
BroadcastDataSourceInput = Union[ManualDataSource, UrlDataSourceInput, WebhookDataSourceInput]


class UrlDataSource(TypedDict):
    type: Literal["url"]
    url: str
    header_name: Optional[str]
    has_header_value: bool


class WebhookDataSource(TypedDict):
    type: Literal["webhook"]
    trigger_url: str
    secret: str


BroadcastDataSource = Union[ManualDataSource, UrlDataSource, WebhookDataSource]


_BroadcastExtra = TypedDict(
    "_BroadcastExtra",
    {
        "object": Literal["broadcast"],
        "from": str,
        "reply_to": Optional[List[str]],
        "preview_text": Optional[str],
        "topic_id": Optional[str],
        "template_id": Optional[str],
        "html": Optional[str],
        "text": Optional[str],
        "open_tracking": bool,
        "click_tracking": bool,
        "finished_at": Optional[str],
        "failure_reason": Optional[str],
        "data": Optional[Dict[str, Any]],
        "data_source": Optional[BroadcastDataSource],
    },
)


class Broadcast(BroadcastListItem, _BroadcastExtra):
    pass


_CreateBroadcastRequired = TypedDict("_CreateBroadcastRequired", {"segment_id": str, "from": str})


class CreateBroadcastInput(_CreateBroadcastRequired, total=False):
    #: Boşsa konu satırı.
    name: str
    topic_id: str
    subject: str
    reply_to: StrOrList
    html: str
    text: str
    #: Şablon kimliği ya da takma adı; `html`/`text` ile birlikte verilmez.
    template_id: str
    preview_text: Optional[str]
    #: `True`: aynı istekte gönderir. `scheduled_at` yalnız bununla anlamlıdır.
    send: bool
    scheduled_at: str
    open_tracking: bool
    click_tracking: bool
    #: `{{{data.*}}}` değişkenlerinin değeri (JSON nesne, ≤ 256 KB).
    data: Optional[Dict[str, Any]]
    data_source: Optional[BroadcastDataSourceInput]
    recurrence: Optional[BroadcastRecurrence]


UpdateBroadcastInput = TypedDict(
    "UpdateBroadcastInput",
    {
        "name": str,
        "segment_id": str,
        "topic_id": Optional[str],
        "from": str,
        "subject": str,
        "reply_to": List[str],
        "html": str,
        "text": str,
        "preview_text": Optional[str],
        "open_tracking": bool,
        "click_tracking": bool,
        # `None` gönderilirse alan temizlenir; anahtarı vermemek değiştirmez.
        "data": Optional[Dict[str, Any]],
        "data_source": Optional[BroadcastDataSourceInput],
        "recurrence": Optional[BroadcastRecurrence],
    },
    total=False,
)


class SendBroadcastInput(TypedDict, total=False):
    scheduled_at: str
    data: Dict[str, Any]


class BroadcastRef(TypedDict):
    object: Literal["broadcast"]
    id: str


# --- brand ---

BrandFontKey = Literal[
    "MODERN_SANS",
    "BOOK_SANS",
    "ORGANIC_SANS",
    "GEOMETRIC_SANS",
    "HEAVY_SANS",
    "ROUNDED_SANS",
    "MODERN_SERIF",
    "BOOK_SERIF",
    "MONOSPACE",
]
BrandButtonStyle = Literal["rectangle", "rounded", "pill"]
BrandLogoAlign = Literal["left", "center", "right"]
BrandSocialNetwork = Literal["website", "x", "facebook", "instagram", "linkedin", "youtube", "github", "tiktok"]


class BrandSocialLink(TypedDict):
    network: BrandSocialNetwork
    url: str


class Brand(TypedDict):
    """Çalışma alanının markası. `configured` marka hiç kaydedilmediyse `False`."""

    object: Literal["brand"]
    configured: bool
    logo_asset_id: Optional[str]
    logo_url: Optional[str]
    logo_dark_asset_id: Optional[str]
    logo_dark_url: Optional[str]
    logo_width: int
    logo_align: BrandLogoAlign
    header_enabled: bool
    accent_color: str
    text_color: str
    backdrop_color: str
    canvas_color: str
    link_color: str
    font_family: BrandFontKey
    button_style: BrandButtonStyle
    content_width: int
    footer_text: Optional[str]
    legal_text: Optional[str]
    postal_address: Optional[str]
    website_url: Optional[str]
    social_links: List[BrandSocialLink]
    unsubscribe_label: str
    updated_at: Optional[str]


class UpdateBrandInput(TypedDict, total=False):
    """Markanın TAMAMINI değiştirir: gönderilmeyen ya da `None` olan alan "ayarlanmadı" olur. Önce `brand.get` ile okuyun."""

    logo_asset_id: Optional[str]
    logo_dark_asset_id: Optional[str]
    logo_width: Optional[int]
    logo_align: Optional[BrandLogoAlign]
    header_enabled: bool
    accent_color: Optional[str]
    text_color: Optional[str]
    backdrop_color: Optional[str]
    canvas_color: Optional[str]
    link_color: Optional[str]
    font_family: Optional[BrandFontKey]
    button_style: Optional[BrandButtonStyle]
    content_width: Optional[int]
    footer_text: Optional[str]
    legal_text: Optional[str]
    postal_address: Optional[str]
    website_url: Optional[str]
    social_links: List[BrandSocialLink]
    unsubscribe_label: Optional[str]


class TemplateBrandOverride(TypedDict, total=False):
    accent_color: str
    text_color: str
    backdrop_color: str
    canvas_color: str
    font_family: BrandFontKey
    link_color: str
    content_width: int
    show_header: bool
    show_footer: bool


class _TemplateBrandRequired(TypedDict):
    mode: Literal["inherit", "custom", "none"]


class TemplateBrand(_TemplateBrandRequired, total=False):
    override: Optional[TemplateBrandOverride]


# --- templates ---


class TemplateListItem(TypedDict):
    id: str
    name: str
    alias: Optional[str]
    type: Literal["design", "html"]
    status: Literal["draft", "published"]
    subject: Optional[str]
    current_version: Optional[int]
    has_unpublished_changes: bool
    published_at: Optional[str]
    created_at: str
    updated_at: str


class TemplateVariable(TypedDict):
    """Şablonda kullanılan değişken: `{{{AD}}}` ya da `{{{AD|yedek}}}`."""

    key: str
    type: Literal["string"]
    fallback_value: Optional[str]


class Template(TemplateListItem):
    object: Literal["template"]
    preview_text: Optional[str]
    html: str
    text: Optional[str]
    design: Any
    revision: int
    variables: List[TemplateVariable]
    brand: TemplateBrand


class _CreateTemplateRequired(TypedDict):
    name: str
    html: str


class CreateTemplateInput(_CreateTemplateRequired, total=False):
    alias: str
    subject: Optional[str]
    preview_text: Optional[str]
    text: Optional[str]
    #: Varsayılan `{"mode": "none"}`: HTML olduğu gibi kalır.
    brand: TemplateBrand


class UpdateTemplateInput(TypedDict, total=False):
    #: Eşzamanlı düzenleme denetimi: önceki okumadaki `revision`.
    revision: int
    name: str
    alias: Optional[str]
    subject: Optional[str]
    preview_text: Optional[str]
    html: str
    text: Optional[str]
    brand: TemplateBrand


class TemplateRef(TypedDict):
    object: Literal["template"]
    id: str


class TemplateSaved(TemplateRef):
    revision: int


class TemplatePublished(TemplateRef):
    version: int
    version_id: str
    revision: int


class _PutTemplateTranslationRequired(TypedDict):
    html: str


class PutTemplateTranslationInput(_PutTemplateTranslationRequired, total=False):
    subject: Optional[str]
    preview_text: Optional[str]
    text: Optional[str]


class TemplateTranslation(TypedDict):
    locale: str
    subject: Optional[str]
    preview_text: Optional[str]
    design_revision: int
    updated_at: str


class TemplateTranslationDeleted(TypedDict):
    object: Literal["template_translation"]
    locale: str
    deleted: Literal[True]


# --- webhooks ---

WebhookEventType = str  # email.sent, email.delivered, contact.created, domain.updated, topic.deleted, …


class Webhook(TypedDict):
    id: str
    endpoint: str
    created_at: str
    status: Literal["enabled", "disabled"]
    events: List[WebhookEventType]


class WebhookDetail(Webhook):
    object: Literal["webhook"]
    signing_secret: str


class CreateWebhookInput(TypedDict):
    #: Herkese açık https adresi.
    endpoint: str
    events: List[WebhookEventType]


class CreatedWebhook(TypedDict):
    object: Literal["webhook"]
    id: str
    #: Yalnız bu yanıtta ve ayrıntıda görünür; `verify_webhook` bununla doğrular.
    signing_secret: str


class UpdateWebhookInput(TypedDict, total=False):
    endpoint: str
    events: List[WebhookEventType]
    status: Literal["enabled", "disabled"]


class WebhookRef(TypedDict):
    object: Literal["webhook"]
    id: str


class WebhookPayload(TypedDict):
    """Webhook gövdesi: `{ type, created_at, data }`."""

    type: WebhookEventType
    created_at: str
    data: Dict[str, Any]


# --- api keys ---

ApiKeyPermission = Literal["full_access", "sending_access"]


class ApiKey(TypedDict):
    id: str
    name: str
    created_at: str
    last_used_at: Optional[str]
    permission: ApiKeyPermission
    domain_id: Optional[str]
    token_prefix: str


class _CreateApiKeyRequired(TypedDict):
    name: str


class CreateApiKeyInput(_CreateApiKeyRequired, total=False):
    #: Varsayılan `full_access`.
    permission: ApiKeyPermission
    #: Yalnız `sending_access` ile: anahtarı bu alan adına kısıtlar.
    domain_id: str


class CreatedApiKey(TypedDict):
    id: str
    #: Tam anahtar yalnız bir kez görünür.
    token: str


# --- events ---

EventProperties = Dict[str, Union[str, int, float, bool, None]]


class _SendEventRequired(TypedDict):
    #: `^[a-z0-9_.:-]{1,64}$`; `email.`, `contact.`, `segment.`, `topic.`, `automation.` ön ekleri ayrılmıştır.
    name: str
    #: `{"email": …}` (yoksa oluşturulur) ya da `{"id": …}` (yoksa 404).
    contact: Dict[str, str]


class SendEventInput(_SendEventRequired, total=False):
    properties: EventProperties
    #: ISO 8601; verilmezse alma anı.
    occurred_at: str
    #: Yalnız kişi bu istekle oluşturuluyorsa: kişiyi abonelikten çıkmış açar.
    unsubscribed: bool


class EventAccepted(TypedDict):
    id: str


class EventBatchResponse(TypedDict):
    data: List[EventAccepted]


class EventItem(TypedDict):
    id: str
    name: str
    contact_id: str
    email: str
    properties: EventProperties
    source: Literal["api", "system"]
    occurred_at: str
    created_at: str


# --- uygulama (Nafru ile bağlan) ---

AppScope = Literal["emails.send", "emails.read", "templates.read", "domains.read", "senders.read", "connection.read"]


class AuthorizeUrl(TypedDict):
    url: str
    #: Yalnız bu bağlanma denemesi için; `exchange` çağrısına kadar sunucunuzda (oturumda) saklayın, tarayıcıya vermeyin.
    code_verifier: str


# `ConnectionGrant` ve `ConnectionTokens` gizli taşıdığından `app.py`'de, `__repr__`'ı maskeli veri sınıflarıdır.


class ConnectionStatus(TypedDict):
    object: Literal["connection"]
    id: str
    ready: bool
    #: Hazır olmak için müşterinin tamamlaması gerekenler: `domain`, `sender`, `plan`.
    missing: List[str]
    hints: List[str]
    scopes: List[str]
    billing_mode: Literal["customer_pays", "app_pays"]
    setup_url: str
    workspace: Dict[str, str]


class SenderDomain(TypedDict):
    id: str
    name: str


class ConnectionSenders(TypedDict):
    domains: List[SenderDomain]
    default_from: Optional[str]


class ConnectionTemplate(TypedDict):
    key: str
    name: str
    source: Literal["workspace", "pack"]
    customized_from_pack: bool
