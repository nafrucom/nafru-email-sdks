//! İstek ve yanıt modelleri. Alan adları ağdaki gibi `snake_case`'tir: dönüştürme katmanı yoktur.
//!
//! İsteğe bağlı ve `null` alabilen alanlar `Option<Option<T>>`'dir: `None` gönderilmez, `Some(None)` `null` gönderir.

use serde::{Deserialize, Deserializer, Serialize, Serializer};
use serde_json::Value;
use std::collections::HashMap;
use std::fmt;

/// Sabit değer kümesi. Sunucunun bu sürümde bilinmeyen yeni değeri `Other` olarak gelir (çözümleme kırılmaz).
macro_rules! str_enum {
    ($(#[$meta:meta])* $name:ident { $($variant:ident = $value:literal),+ $(,)? }) => {
        $(#[$meta])*
        #[derive(Debug, Clone, PartialEq, Eq, Hash)]
        pub enum $name {
            $($variant,)+
            Other(String),
        }

        impl $name {
            pub fn as_str(&self) -> &str {
                match self {
                    $(Self::$variant => $value,)+
                    Self::Other(value) => value,
                }
            }
        }

        impl fmt::Display for $name {
            fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
                f.write_str(self.as_str())
            }
        }

        impl Serialize for $name {
            fn serialize<S: Serializer>(&self, serializer: S) -> Result<S::Ok, S::Error> {
                serializer.serialize_str(self.as_str())
            }
        }

        impl<'de> Deserialize<'de> for $name {
            fn deserialize<D: Deserializer<'de>>(deserializer: D) -> Result<Self, D::Error> {
                let value = String::deserialize(deserializer)?;
                Ok(match value.as_str() {
                    $($value => Self::$variant,)+
                    _ => Self::Other(value),
                })
            }
        }
    };
}

/// Liste öğeleri için sayfalama imleci.
pub trait HasId {
    fn id(&self) -> &str;
}

macro_rules! has_id {
    ($($name:ty),+ $(,)?) => {
        $(impl HasId for $name {
            fn id(&self) -> &str {
                &self.id
            }
        })+
    };
}

// ---------- ortak ----------

/// Sunucunun `{ object: 'list', data, has_more }` liste zarfı.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ListResponse<T> {
    pub object: String,
    pub data: Vec<T>,
    pub has_more: bool,
}

/// İmleçli liste sorgusu: `after` ve `before` birlikte verilemez.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListQuery {
    /// 1–100, varsayılan 20.
    pub limit: Option<u32>,
    /// Bu kimlikten sonraki kayıtlar.
    pub after: Option<String>,
    /// Bu kimlikten önceki kayıtlar.
    pub before: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeletedResponse {
    pub object: String,
    pub id: String,
    pub deleted: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Tag {
    pub name: String,
    pub value: String,
}

/// Yalnız `id` taşıyan yanıt (`{ object, id }` biçimli referanslar dahil).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct IdRef {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub object: Option<String>,
    pub id: String,
}

// ---------- e-postalar ----------

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Attachment {
    /// Base64 metni. `path` ile birlikte verilmez.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content: Option<String>,
    /// Herkese açık https adresi. `content` ile birlikte verilmez.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub path: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filename: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_type: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_id: Option<String>,
}

/// Şablonla gönderim: `html`/`text`/`attachments` ile birlikte verilmez.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
pub struct EmailTemplate {
    /// Şablon kimliği ya da takma adı.
    pub id: String,
    /// Değerler metin ya da sayı.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub variables: Option<HashMap<String, Value>>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct SendEmailInput {
    /// `Ad <adres@alan.com>` ya da adres. Şablonla gönderimde isteğe bağlıdır (çalışma alanı varsayılanı).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
    pub to: Vec<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cc: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bcc: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub headers: Option<HashMap<String, String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<Tag>>,
    /// ISO 8601 ya da göreli ifade (`in 1 hour`). Geçmiş an hemen gönderir; en fazla 30 gün sonrası.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub attachments: Option<Vec<Attachment>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub template: Option<EmailTemplate>,
}

/// Toplu öğe: ek ve şablon desteklenmez.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct BatchEmailItem {
    pub from: String,
    pub to: Vec<String>,
    pub subject: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub cc: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub bcc: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub headers: Option<HashMap<String, String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tags: Option<Vec<Tag>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SendEmailOptions {
    /// `Idempotency-Key`: aynı anahtarla yinelenen istek aynı e-postayı döndürür.
    pub idempotency_key: Option<String>,
}

impl SendEmailOptions {
    pub fn idempotency_key(key: impl Into<String>) -> Self {
        Self {
            idempotency_key: Some(key.into()),
        }
    }
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SendEmailResponse {
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BatchEmailResponse {
    pub data: Vec<SendEmailResponse>,
}

str_enum!(EmailStatus {
    Queued = "queued",
    Scheduled = "scheduled",
    Sent = "sent",
    Delivered = "delivered",
    DeliveryDelayed = "delivery_delayed",
    Bounced = "bounced",
    Complained = "complained",
    Failed = "failed",
    Canceled = "canceled",
});

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EmailListItem {
    pub id: String,
    pub to: Vec<String>,
    pub from: String,
    pub created_at: String,
    pub subject: String,
    pub bcc: Option<Vec<String>>,
    pub cc: Option<Vec<String>>,
    pub reply_to: Option<Vec<String>>,
    pub last_event: EmailStatus,
    pub scheduled_at: Option<String>,
    pub message_id: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EmailEvent {
    pub id: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub created_at: String,
    pub detail: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Email {
    #[serde(flatten)]
    pub item: EmailListItem,
    pub object: String,
    pub html: Option<String>,
    pub text: Option<String>,
    pub tags: Vec<Tag>,
    pub events: Vec<EmailEvent>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListEmailsQuery {
    pub limit: Option<u32>,
    pub after: Option<String>,
    pub before: Option<String>,
    pub status: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct UpdateEmailInput {
    pub scheduled_at: String,
}

// ---------- alan adları ----------

str_enum!(DomainStatus {
    NotStarted = "not_started",
    Pending = "pending",
    Verified = "verified",
    Failed = "failed",
    TemporaryFailure = "temporary_failure",
});

str_enum!(DomainTls { Opportunistic = "opportunistic", Enforced = "enforced" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DomainRecord {
    /// `SPF`, `DKIM`, `Tracking`.
    pub record: String,
    pub name: String,
    /// `MX`, `TXT`, `CNAME`.
    #[serde(rename = "type")]
    pub kind: String,
    pub value: String,
    pub ttl: String,
    pub status: DomainStatus,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub priority: Option<u32>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DomainCapabilities {
    pub sending: String,
    pub receiving: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Domain {
    pub id: String,
    pub name: String,
    pub status: DomainStatus,
    pub created_at: String,
    pub region: String,
    pub capabilities: DomainCapabilities,
    pub open_tracking: bool,
    pub click_tracking: bool,
    pub tls: DomainTls,
    pub tracking_subdomain: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DomainDetail {
    #[serde(flatten)]
    pub domain: Domain,
    pub object: String,
    pub records: Vec<DomainRecord>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct CreateDomainInput {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub region: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub click_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<DomainTls>,
    /// Örn. `track` → `track.<alan-adı>`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tracking_subdomain: Option<String>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateDomainInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub click_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tls: Option<DomainTls>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub tracking_subdomain: Option<Option<String>>,
}

// ---------- kişiler ----------

/// Kişi alanı değeri: metin, sayı ya da `null`.
pub type PropertyValue = Value;

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Contact {
    pub id: String,
    pub email: String,
    pub first_name: Option<String>,
    pub last_name: Option<String>,
    pub unsubscribed: bool,
    /// ISO 639-1 ana dil kodu; bölgeli kod (`pt-BR`) sunucuda ana dile indirgenir.
    pub locale: Option<String>,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContactPropertyValue {
    /// `string` ya da `number`.
    #[serde(rename = "type")]
    pub kind: String,
    pub value: Value,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContactDetail {
    #[serde(flatten)]
    pub contact: Contact,
    pub object: String,
    /// Yalnız değeri olan alanlar.
    pub properties: HashMap<String, ContactPropertyValue>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SubscriptionRef {
    pub id: String,
    pub subscription: TopicSubscription,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SegmentId {
    pub id: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct CreateContactInput {
    pub email: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_name: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_name: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unsubscribed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locale: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub properties: Option<HashMap<String, PropertyValue>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segments: Option<Vec<SegmentId>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub topics: Option<Vec<SubscriptionRef>>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct UpdateContactInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub first_name: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub last_name: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unsubscribed: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub locale: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub properties: Option<HashMap<String, PropertyValue>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListContactsQuery {
    pub limit: Option<u32>,
    pub after: Option<String>,
    pub before: Option<String>,
    /// E-posta, ad ya da soyad içinde arar.
    pub search: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeletedContact {
    pub object: String,
    pub contact: String,
    pub deleted: bool,
}

str_enum!(PropertyType { String = "string", Number = "number" });

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContactProperty {
    pub id: String,
    pub key: String,
    #[serde(rename = "type")]
    pub kind: PropertyType,
    pub fallback_value: Option<Value>,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ContactPropertyDetail {
    #[serde(flatten)]
    pub property: ContactProperty,
    pub object: String,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct CreateContactPropertyInput {
    pub key: String,
    #[serde(rename = "type")]
    pub kind: PropertyType,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_value: Option<Value>,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct UpdateContactPropertyInput {
    /// `Some(Value::Null)` yedeği siler.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub fallback_value: Option<Value>,
}

// ---------- segmentler ----------

str_enum!(SegmentType { Static = "static", Dynamic = "dynamic" });

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Segment {
    pub id: String,
    pub name: String,
    pub created_at: String,
    #[serde(rename = "type")]
    pub kind: SegmentType,
    pub filter: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct SegmentDetail {
    #[serde(flatten)]
    pub segment: Segment,
    pub object: String,
}

#[derive(Debug, Clone, Default, PartialEq, Serialize)]
pub struct CreateSegmentInput {
    pub name: String,
    /// Verilirse dinamik segment.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub filter: Option<Value>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SegmentRef {
    pub object: String,
    pub id: String,
    pub name: String,
}

/// Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct SegmentContactsQuery {
    pub limit: Option<u32>,
    pub after: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct DeletedLink {
    pub id: String,
    pub deleted: bool,
}

// ---------- konular ----------

str_enum!(TopicSubscription { OptIn = "opt_in", OptOut = "opt_out" });
str_enum!(Visibility { Public = "public", Private = "private" });
str_enum!(ContactTopicStatus { OptIn = "opt_in", OptOut = "opt_out", Pending = "pending" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Topic {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub default_subscription: TopicSubscription,
    pub visibility: Visibility,
    pub double_opt_in: bool,
    pub created_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TopicDetail {
    #[serde(flatten)]
    pub topic: Topic,
    pub object: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CreateTopicInput {
    pub name: String,
    pub default_subscription: TopicSubscription,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub double_opt_in: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateTopicInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub description: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub visibility: Option<Visibility>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub double_opt_in: Option<bool>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ContactTopic {
    pub id: String,
    pub name: String,
    pub description: Option<String>,
    pub subscription: TopicSubscription,
    /// `pending`: çift onay bekliyor (`subscription` bu durumda `opt_out` görünür).
    pub status: ContactTopicStatus,
}

/// Sunucu gövdede çıplak dizi bekler; SDK `topics` dizisini doğrudan gönderir.
#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct UpdateContactTopicsInput {
    pub topics: Vec<SubscriptionRef>,
}

// ---------- kampanyalar ----------

str_enum!(BroadcastStatus {
    Draft = "draft",
    Scheduled = "scheduled",
    Sending = "sending",
    Sent = "sent",
    Paused = "paused",
    Canceled = "canceled",
    Failed = "failed",
});

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BroadcastListItem {
    pub id: String,
    pub name: String,
    pub segment_id: String,
    pub audience_id: String,
    pub subject: String,
    pub status: BroadcastStatus,
    pub created_at: String,
    pub scheduled_at: Option<String>,
    pub sent_at: Option<String>,
    /// Tekrar kuralı (şablon kaydında); yoksa `None`.
    pub recurrence: Option<BroadcastRecurrence>,
    /// Şablonun tetik durumu; `None` = başlatılmadı.
    pub trigger_state: Option<BroadcastTriggerState>,
    /// Sonraki zamanlı çalışma (ISO 8601).
    pub next_run_at: Option<String>,
    /// Çalışma örneğinde şablonun kimliği.
    pub parent_id: Option<String>,
}

str_enum!(BroadcastTriggerState { Active = "active", Paused = "paused" });

/// `{{{data.*}}}` bağlamı: JSON nesnesi.
pub type BroadcastData = serde_json::Map<String, Value>;

/// Tekrar kuralı; saat (`HH:MM`) çalışma alanının saat dilimindedir. `weekly.days`: 0 = pazar … 6 = cumartesi.
/// `monthly.day`: 1–31 (ay kısaysa ayın son günü). `interval.every_days`: 1–365 gün.
/// Bu sürümün bilmediği bir `type` `Unknown` olarak çözülür (göndermek için kullanmayın).
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BroadcastRecurrence {
    Weekly {
        days: Vec<u8>,
        time: String,
    },
    Monthly {
        day: u8,
        time: String,
    },
    Interval {
        every_days: u32,
        time: String,
    },
    #[serde(other)]
    Unknown,
}

/// `{{{data.*}}}` değişkenlerinin kaynağı. `Url`: gönderim anında `GET` (https, ≤ 256 KB JSON nesne, 10 sn). `Webhook`: imzalı tetik ucu.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BroadcastDataSourceInput {
    Manual,
    Url {
        url: String,
        #[serde(skip_serializing_if = "Option::is_none")]
        header_name: Option<Option<String>>,
        #[serde(skip_serializing_if = "Option::is_none")]
        header_value: Option<Option<String>>,
    },
    Webhook {
        #[serde(skip_serializing_if = "Option::is_none")]
        regenerate_secret: Option<bool>,
    },
}

/// Yanıttaki veri kaynağı; bilinmeyen `type` `Unknown` olur.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(tag = "type", rename_all = "snake_case")]
pub enum BroadcastDataSource {
    Manual,
    Url {
        url: String,
        header_name: Option<String>,
        has_header_value: bool,
    },
    Webhook {
        trigger_url: String,
        secret: String,
    },
    #[serde(other)]
    Unknown,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Broadcast {
    #[serde(flatten)]
    pub item: BroadcastListItem,
    pub object: String,
    pub from: String,
    pub reply_to: Option<Vec<String>>,
    pub preview_text: Option<String>,
    pub topic_id: Option<String>,
    pub template_id: Option<String>,
    pub html: Option<String>,
    pub text: Option<String>,
    pub open_tracking: bool,
    pub click_tracking: bool,
    pub finished_at: Option<String>,
    pub failure_reason: Option<String>,
    /// Şablondaki `{{{data.*}}}` bağlamı (gönderilmiş örnekte gönderim anında çözülen değer).
    pub data: Option<BroadcastData>,
    pub data_source: Option<BroadcastDataSource>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct CreateBroadcastInput {
    /// Boşsa konu satırı.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    pub segment_id: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub topic_id: Option<String>,
    pub from: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    /// Şablon kimliği ya da takma adı; `html`/`text` ile birlikte verilmez.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub template_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_text: Option<Option<String>>,
    /// `true`: aynı istekte gönderir. `scheduled_at` yalnız bununla anlamlıdır.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub send: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_at: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub click_tracking: Option<bool>,
    /// `{{{data.*}}}` değişkenlerinin değeri (JSON nesne, ≤ 256 KB); `Some(None)` `null` gönderir.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Option<BroadcastData>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_source: Option<Option<BroadcastDataSourceInput>>,
    /// Verilirse kayıt tekrarlayan bir şablondur: `send` onu başlatmaz, etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recurrence: Option<Option<BroadcastRecurrence>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateBroadcastInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub segment_id: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub topic_id: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub from: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub reply_to: Option<Vec<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_text: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub open_tracking: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub click_tracking: Option<bool>,
    /// `{{{data.*}}}` değişkenlerinin değeri (JSON nesne, ≤ 256 KB); `Some(None)` `null` gönderir.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<Option<BroadcastData>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data_source: Option<Option<BroadcastDataSourceInput>>,
    /// Verilirse kayıt tekrarlayan bir şablondur: `send` onu başlatmaz, etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recurrence: Option<Option<BroadcastRecurrence>>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct SendBroadcastInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub scheduled_at: Option<String>,
    /// Bu gönderimin `{{{data.*}}}` bağlamı (taslaktakinin yerine).
    #[serde(skip_serializing_if = "Option::is_none")]
    pub data: Option<BroadcastData>,
}

// ---------- marka ----------

str_enum!(BrandFontKey {
    ModernSans = "MODERN_SANS",
    BookSans = "BOOK_SANS",
    OrganicSans = "ORGANIC_SANS",
    GeometricSans = "GEOMETRIC_SANS",
    HeavySans = "HEAVY_SANS",
    RoundedSans = "ROUNDED_SANS",
    ModernSerif = "MODERN_SERIF",
    BookSerif = "BOOK_SERIF",
    Monospace = "MONOSPACE",
});
str_enum!(BrandButtonStyle { Rectangle = "rectangle", Rounded = "rounded", Pill = "pill" });
str_enum!(BrandLogoAlign { Left = "left", Center = "center", Right = "right" });
str_enum!(BrandSocialNetwork {
    Website = "website",
    X = "x",
    Facebook = "facebook",
    Instagram = "instagram",
    Linkedin = "linkedin",
    Youtube = "youtube",
    Github = "github",
    Tiktok = "tiktok",
});

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct BrandSocialLink {
    pub network: BrandSocialNetwork,
    /// http(s) adresi.
    pub url: String,
}

/// Çalışma alanının markası. Ayarlanmamış renk/yazı tipi/genişlik varsayılan değerle döner; `configured` marka hiç kaydedilmediyse `false`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Brand {
    pub object: String,
    pub configured: bool,
    pub logo_asset_id: Option<String>,
    pub logo_url: Option<String>,
    pub logo_dark_asset_id: Option<String>,
    pub logo_dark_url: Option<String>,
    /// px, 40–400.
    pub logo_width: u32,
    pub logo_align: BrandLogoAlign,
    pub header_enabled: bool,
    pub accent_color: String,
    pub text_color: String,
    pub backdrop_color: String,
    pub canvas_color: String,
    pub link_color: String,
    pub font_family: BrandFontKey,
    pub button_style: BrandButtonStyle,
    /// px, 480–720.
    pub content_width: u32,
    pub footer_text: Option<String>,
    pub legal_text: Option<String>,
    pub postal_address: Option<String>,
    pub website_url: Option<String>,
    pub social_links: Vec<BrandSocialLink>,
    pub unsubscribe_label: String,
    pub updated_at: Option<String>,
}

/// `brand.update` markanın TAMAMINI değiştirir: gönderilmeyen ya da `null` olan alan "ayarlanmadı" olur. Önce `brand.get` ile okuyun.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateBrandInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_asset_id: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_dark_asset_id: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_width: Option<Option<u32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub logo_align: Option<Option<BrandLogoAlign>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub header_enabled: Option<bool>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub accent_color: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text_color: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub backdrop_color: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub canvas_color: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub link_color: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub font_family: Option<Option<BrandFontKey>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub button_style: Option<Option<BrandButtonStyle>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub content_width: Option<Option<u32>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub footer_text: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub legal_text: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub postal_address: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub website_url: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub social_links: Option<Vec<BrandSocialLink>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unsubscribe_label: Option<Option<String>>,
}

/// Şablon başına markayı ezen alanlar (yalnız `custom` kipte).
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateBrandOverride {
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub accent_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub text_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub backdrop_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub canvas_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub font_family: Option<BrandFontKey>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_color: Option<String>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub content_width: Option<u32>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub show_header: Option<bool>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub show_footer: Option<bool>,
}

str_enum!(TemplateBrandMode { Inherit = "inherit", Custom = "custom", None = "none" });

/// Şablonun marka kipi: `inherit` marka olduğu gibi, `custom` marka + `override`, `none` hiçbir şey eklenmez.
/// Pazarlama şablonunda `custom` ile `show_footer: false` 422 verir: altbilgi çıkma bağlantısını taşır.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateBrand {
    pub mode: TemplateBrandMode,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub r#override: Option<TemplateBrandOverride>,
}

// ---------- şablonlar ----------

str_enum!(TemplateType { Design = "design", Html = "html" });
str_enum!(TemplateStatus { Draft = "draft", Published = "published" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateListItem {
    pub id: String,
    pub name: String,
    pub alias: Option<String>,
    #[serde(rename = "type")]
    pub kind: TemplateType,
    pub status: TemplateStatus,
    pub subject: Option<String>,
    pub current_version: Option<u32>,
    pub has_unpublished_changes: bool,
    pub published_at: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

/// Şablonda kullanılan değişken: `{{{AD}}}` ya da `{{{AD|yedek}}}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateVariable {
    pub key: String,
    #[serde(rename = "type")]
    pub kind: String,
    pub fallback_value: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct Template {
    #[serde(flatten)]
    pub item: TemplateListItem,
    pub object: String,
    pub preview_text: Option<String>,
    pub html: String,
    pub text: Option<String>,
    pub design: Value,
    pub revision: u64,
    pub variables: Vec<TemplateVariable>,
    pub brand: TemplateBrand,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct CreateTemplateInput {
    pub name: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alias: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_text: Option<Option<String>>,
    pub html: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<Option<String>>,
    /// Varsayılan `{ mode: 'none' }`: HTML olduğu gibi kalır.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub brand: Option<TemplateBrand>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateTemplateInput {
    /// Eşzamanlı düzenleme denetimi: önceki okumadaki `revision`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub revision: Option<u64>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub name: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub alias: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_text: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub html: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub brand: Option<TemplateBrand>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateSaved {
    pub object: String,
    pub id: String,
    pub revision: u64,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplatePublished {
    pub object: String,
    pub id: String,
    pub version: u64,
    pub version_id: String,
    pub revision: u64,
}

/// Bir dilin taslağı. API anahtarıyla yalnız `html` türü şablonda; `locale` BCP 47, ana dile indirgenir.
#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct PutTemplateTranslationInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub subject: Option<Option<String>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub preview_text: Option<Option<String>>,
    pub html: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub text: Option<Option<String>>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateTranslation {
    pub locale: String,
    pub subject: Option<String>,
    pub preview_text: Option<String>,
    pub design_revision: u64,
    pub updated_at: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct TemplateTranslationDeleted {
    pub object: String,
    pub locale: String,
    pub deleted: bool,
}

// ---------- webhook'lar ----------

str_enum!(WebhookEventType {
    EmailSent = "email.sent",
    EmailScheduled = "email.scheduled",
    EmailDelivered = "email.delivered",
    EmailDeliveryDelayed = "email.delivery_delayed",
    EmailComplained = "email.complained",
    EmailBounced = "email.bounced",
    EmailOpened = "email.opened",
    EmailClicked = "email.clicked",
    EmailReceived = "email.received",
    EmailFailed = "email.failed",
    EmailSuppressed = "email.suppressed",
    ContactCreated = "contact.created",
    ContactUpdated = "contact.updated",
    ContactDeleted = "contact.deleted",
    ContactTopicsUpdated = "contact.topics.updated",
    DomainCreated = "domain.created",
    DomainUpdated = "domain.updated",
    DomainDeleted = "domain.deleted",
    SuppressionAdded = "suppression.added",
    SuppressionRemoved = "suppression.removed",
    TopicCreated = "topic.created",
    TopicUpdated = "topic.updated",
    TopicDeleted = "topic.deleted",
});
str_enum!(WebhookStatus { Enabled = "enabled", Disabled = "disabled" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Webhook {
    pub id: String,
    pub endpoint: String,
    pub created_at: String,
    pub status: WebhookStatus,
    pub events: Vec<WebhookEventType>,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct WebhookDetail {
    #[serde(flatten)]
    pub webhook: Webhook,
    pub object: String,
    pub signing_secret: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
pub struct CreateWebhookInput {
    /// Herkese açık https adresi.
    pub endpoint: String,
    pub events: Vec<WebhookEventType>,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreatedWebhook {
    pub object: String,
    pub id: String,
    /// Yalnız bu yanıtta ve ayrıntıda görünür; `verify_webhook` bununla doğrular.
    pub signing_secret: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct UpdateWebhookInput {
    #[serde(skip_serializing_if = "Option::is_none")]
    pub endpoint: Option<String>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub events: Option<Vec<WebhookEventType>>,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub status: Option<WebhookStatus>,
}

/// Webhook gövdesi: `{ type, created_at, data }`.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WebhookPayload<T = Value> {
    #[serde(rename = "type")]
    pub kind: WebhookEventType,
    pub created_at: String,
    pub data: T,
}

// ---------- API anahtarları ----------

str_enum!(ApiKeyPermission { FullAccess = "full_access", SendingAccess = "sending_access" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ApiKey {
    pub id: String,
    pub name: String,
    pub created_at: String,
    pub last_used_at: Option<String>,
    pub permission: ApiKeyPermission,
    pub domain_id: Option<String>,
    pub token_prefix: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct CreateApiKeyInput {
    pub name: String,
    /// Varsayılan `full_access`.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub permission: Option<ApiKeyPermission>,
    /// Yalnız `sending_access` ile: anahtarı bu alan adına kısıtlar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub domain_id: Option<String>,
}

#[derive(Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct CreatedApiKey {
    pub id: String,
    /// Tam anahtar yalnız bir kez görünür.
    pub token: String,
}

// ---------- olaylar ----------

/// Olay özellikleri: metin, sayı, mantıksal ya da `null`.
pub type EventProperties = HashMap<String, Value>;

/// E-posta ile verilen kişi yoksa oluşturulur; kimlikle verilen yoksa 404.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(untagged)]
pub enum EventContact {
    Email { email: String },
    Id { id: String },
}

#[derive(Debug, Clone, PartialEq, Serialize)]
pub struct SendEventInput {
    /// `^[a-z0-9_.:-]{1,64}$`; `email.`, `contact.`, `segment.`, `topic.`, `automation.` ön ekleri ayrılmıştır.
    pub name: String,
    pub contact: EventContact,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub properties: Option<EventProperties>,
    /// ISO 8601; verilmezse alma anı.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub occurred_at: Option<String>,
    /// Yalnız kişi bu istekle oluşturuluyorsa: kişiyi abonelikten çıkmış açar.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub unsubscribed: Option<bool>,
}

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct SendEventOptions {
    /// `Idempotency-Key`: aynı anahtarla yinelenen istek olayı bir kez işler.
    pub idempotency_key: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventAccepted {
    pub id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct EventBatchResponse {
    pub data: Vec<EventAccepted>,
}

str_enum!(EventSource { Api = "api", System = "system" });

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct EventItem {
    pub id: String,
    pub name: String,
    pub contact_id: String,
    pub email: String,
    pub properties: EventProperties,
    pub source: EventSource,
    pub occurred_at: String,
    pub created_at: String,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize)]
pub struct ListEventsQuery {
    pub limit: Option<u32>,
    pub after: Option<String>,
    pub before: Option<String>,
    /// Tam eşleşme; sistem olay adlarını (`email.opened`) da kabul eder.
    pub name: Option<String>,
    pub contact_id: Option<String>,
    /// `contact_id` ile birlikte verilmez.
    pub email: Option<String>,
}

// ---------- Nafru ile bağlan ----------

str_enum!(
    /// Uygulamanın müşteriden isteyebileceği izinler.
    AppScope {
        EmailsSend = "emails.send",
        EmailsRead = "emails.read",
        TemplatesRead = "templates.read",
        DomainsRead = "domains.read",
        SendersRead = "senders.read",
        ConnectionRead = "connection.read",
    }
);

#[derive(Debug, Clone, Default, PartialEq, Eq)]
pub struct AuthorizeUrlInput {
    /// Kayıtlı yönlendirme adresiyle birebir aynı olmalı.
    pub redirect_uri: String,
    /// CSRF koruması: istekten önce üretip oturumda saklayın, dönüşte karşılaştırın. Zorunlu.
    pub state: String,
    pub scopes: Vec<AppScope>,
    /// Müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir.
    pub login_hint: Option<String>,
}

#[derive(Clone, PartialEq, Eq)]
pub struct AuthorizeUrl {
    pub url: String,
    /// Yalnız bu bağlanma denemesi için; `exchange` çağrısına kadar sunucunuzda (oturumda) saklayın, tarayıcıya vermeyin.
    pub code_verifier: String,
}

#[derive(Clone, Default, PartialEq, Eq)]
pub struct ExchangeInput {
    pub code: String,
    pub code_verifier: String,
    pub redirect_uri: String,
}

#[derive(Clone, PartialEq, Eq)]
pub struct ConnectionGrant {
    /// `conn_…`: müşteri bağlantısının kalıcı kimliği (kendi veritabanınızda müşteriyle eşleyin).
    pub connection_id: String,
    /// Şifreleyerek saklayın; tarayıcıya vermeyin. Her yenilemede değişir (`on_token_refresh`).
    pub refresh_token: String,
    pub scopes: Vec<AppScope>,
}

#[derive(Clone, PartialEq, Eq)]
pub struct ConnectionTokens {
    pub refresh_token: String,
}

str_enum!(BillingMode { CustomerPays = "customer_pays", AppPays = "app_pays" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionWorkspace {
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionStatus {
    pub object: String,
    pub id: String,
    pub ready: bool,
    /// Hazır olmak için müşterinin tamamlaması gerekenler: `domain`, `sender`, `plan`.
    pub missing: Vec<String>,
    pub hints: Vec<String>,
    pub scopes: Vec<AppScope>,
    pub billing_mode: BillingMode,
    pub setup_url: String,
    pub workspace: ConnectionWorkspace,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct SenderDomain {
    pub id: String,
    pub name: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionSenders {
    pub domains: Vec<SenderDomain>,
    pub default_from: Option<String>,
}

str_enum!(TemplateSource { Workspace = "workspace", Pack = "pack" });

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ConnectionTemplate {
    pub key: String,
    pub name: String,
    pub source: TemplateSource,
    pub customized_from_pack: bool,
}

has_id!(
    EmailListItem,
    Domain,
    Contact,
    ContactProperty,
    Segment,
    Topic,
    ContactTopic,
    BroadcastListItem,
    TemplateListItem,
    Webhook,
    ApiKey,
    EventItem,
);

redacted_debug!(WebhookDetail { webhook, object } secret { signing_secret });
redacted_debug!(CreatedWebhook { object, id } secret { signing_secret });
redacted_debug!(CreatedApiKey { id } secret { token });
redacted_debug!(AuthorizeUrl { url } secret { code_verifier });
redacted_debug!(ExchangeInput { redirect_uri } secret { code, code_verifier });
redacted_debug!(ConnectionGrant { connection_id, scopes } secret { refresh_token });
redacted_debug!(ConnectionTokens {} secret { refresh_token });
