use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::fmt;

/// 422 yanıtındaki alan ayrıntısı.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct NafruFieldError {
    pub field: String,
    pub message: String,
    #[serde(
        rename = "i18nTranslationKey",
        default,
        skip_serializing_if = "Option::is_none"
    )]
    pub i18n_translation_key: Option<String>,
}

/// Her başarısız çağrının hatası. `status_code` ağ hatalarında `None`'dır. `name`, sunucunun hata adıdır
/// (`validation_error`, `rate_limit_exceeded`, `not_found`, …); ağ ve zaman aşımı için `application_error` / `timeout_error`.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct NafruError {
    pub status_code: Option<u16>,
    pub name: String,
    pub message: String,
    pub errors: Vec<NafruFieldError>,
    /// `429` yanıtındaki `retry-after` (saniye).
    pub retry_after: Option<u64>,
}

pub type Result<T> = std::result::Result<T, NafruError>;

impl fmt::Display for NafruError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        match self.status_code {
            Some(status) => write!(f, "{} ({}): {}", self.name, status, self.message),
            None => write!(f, "{}: {}", self.name, self.message),
        }
    }
}

impl std::error::Error for NafruError {}

impl NafruError {
    pub(crate) fn new(status_code: Option<u16>, name: &str, message: impl Into<String>) -> Self {
        Self {
            status_code,
            name: name.into(),
            message: message.into(),
            errors: Vec::new(),
            retry_after: None,
        }
    }

    pub(crate) fn network(message: impl Into<String>) -> Self {
        Self::new(None, "application_error", message)
    }

    pub(crate) fn timeout(timeout_ms: u128) -> Self {
        Self::new(
            None,
            "timeout_error",
            format!("İstek {timeout_ms} ms içinde tamamlanmadı"),
        )
    }

    /// Yanlış yapılandırma (eksik `api_key`, bozuk webhook anahtarı, …): istek gönderilmeden döner.
    pub(crate) fn invalid(message: impl Into<String>) -> Self {
        Self::new(None, "invalid_argument", message)
    }
}

fn name_by_status(status: u16) -> &'static str {
    match status {
        400 => "invalid_request",
        401 => "unauthorized",
        403 => "forbidden",
        404 => "not_found",
        409 => "conflict",
        413 => "payload_too_large",
        422 => "validation_error",
        429 => "rate_limit_exceeded",
        _ => "application_error",
    }
}

/// Standart gövde (`statusCode`, `name`, `message`, `errors`) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde).
pub(crate) fn parse_error(
    status: u16,
    status_text: &str,
    retry_after: Option<u64>,
    body: &Value,
) -> NafruError {
    if let Some(message) = body.get("message").and_then(Value::as_str) {
        let errors = body
            .get("errors")
            .and_then(Value::as_array)
            .map(|entries| {
                entries
                    .iter()
                    .filter(|entry| entry.is_object())
                    .map(|entry| NafruFieldError {
                        field: entry
                            .get("field")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .into(),
                        message: entry
                            .get("message")
                            .and_then(Value::as_str)
                            .unwrap_or_default()
                            .into(),
                        i18n_translation_key: entry
                            .get("i18nTranslationKey")
                            .and_then(Value::as_str)
                            .map(Into::into),
                    })
                    .collect()
            })
            .unwrap_or_default();
        return NafruError {
            status_code: Some(
                body.get("statusCode")
                    .and_then(Value::as_u64)
                    .and_then(|code| u16::try_from(code).ok())
                    .unwrap_or(status),
            ),
            name: body
                .get("name")
                .and_then(Value::as_str)
                .unwrap_or(name_by_status(status))
                .into(),
            message: message.into(),
            errors,
            retry_after,
        };
    }
    NafruError {
        status_code: Some(status),
        name: name_by_status(status).into(),
        message: if status_text.is_empty() {
            format!("HTTP {status}")
        } else {
            status_text.into()
        },
        errors: Vec::new(),
        retry_after,
    }
}
