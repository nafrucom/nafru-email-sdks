use crate::app::TokenManager;
use crate::error::{NafruError, Result, parse_error};
use serde::Serialize;
use serde::de::DeserializeOwned;
use serde_json::Value;
use std::future::Future;
use std::pin::Pin;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use std::time::Duration;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Taşıyıcıya giden ham istek. Başlık adları küçük harflidir. `Debug` çıktısında `authorization` gizlenir.
#[derive(Clone, PartialEq, Eq)]
pub struct HttpRequest {
    pub method: &'static str,
    pub url: String,
    pub headers: Vec<(String, String)>,
    pub body: Option<String>,
}

impl std::fmt::Debug for HttpRequest {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let headers: Vec<(&str, &str)> = self
            .headers
            .iter()
            .map(|(name, value)| {
                let secret = name.eq_ignore_ascii_case("authorization");
                (
                    name.as_str(),
                    if secret {
                        crate::REDACTED
                    } else {
                        value.as_str()
                    },
                )
            })
            .collect();
        f.debug_struct("HttpRequest")
            .field("method", &self.method)
            .field("url", &self.url)
            .field("headers", &headers)
            .field("body", &self.body)
            .finish()
    }
}

impl HttpRequest {
    pub fn header(&self, name: &str) -> Option<&str> {
        find_header(&self.headers, name)
    }
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct HttpResponse {
    pub status: u16,
    /// Durum metni (`Bad Gateway`); standart gövde yoksa hata iletisi olur.
    pub status_text: String,
    pub headers: Vec<(String, String)>,
    pub body: String,
}

fn find_header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers
        .iter()
        .find(|(key, _)| key.eq_ignore_ascii_case(name))
        .map(|(_, value)| value.as_str())
}

/// Özel taşıyıcı (test, proxy). Ağ hatasında `Err(ileti)` döner; zaman aşımını SDK uygular.
pub trait Transport: Send + Sync {
    fn send(
        &self,
        request: HttpRequest,
    ) -> BoxFuture<'_, std::result::Result<HttpResponse, String>>;
}

/// Yanıt gövdesi üst sınırı: bozuk ya da kötü niyetli bir ara katman belleği tüketemez.
pub(crate) const MAX_RESPONSE_BYTES: usize = 10 * 1024 * 1024;

/// Varsayılan taşıyıcı: `reqwest` (rustls, sertifika doğrulaması açık). Yönlendirme İZLENMEZ: API yönlendirmez; izlemek
/// `Authorization`'ı başka bir sunucuya sızdırabilir. Gövde en çok `MAX_RESPONSE_BYTES`'a kadar okunur.
#[derive(Debug, Clone)]
pub struct ReqwestTransport {
    client: reqwest::Client,
}

impl Default for ReqwestTransport {
    fn default() -> Self {
        let client = reqwest::Client::builder()
            .redirect(reqwest::redirect::Policy::none())
            .build()
            .expect("reqwest istemcisi kurulamadı (TLS arka ucu)");
        Self { client }
    }
}

impl ReqwestTransport {
    /// Kendi istemciniz: yönlendirmeyi kapatın (`redirect::Policy::none()`) ve sertifika doğrulamasını açık bırakın.
    pub fn new(client: reqwest::Client) -> Self {
        Self { client }
    }
}

impl Transport for ReqwestTransport {
    fn send(
        &self,
        request: HttpRequest,
    ) -> BoxFuture<'_, std::result::Result<HttpResponse, String>> {
        Box::pin(async move {
            let method = reqwest::Method::from_bytes(request.method.as_bytes())
                .map_err(|e| e.to_string())?;
            let mut builder = self.client.request(method, &request.url);
            for (name, value) in &request.headers {
                builder = builder.header(name, value);
            }
            if let Some(body) = request.body {
                builder = builder.body(body);
            }
            let mut response = builder.send().await.map_err(|e| e.to_string())?;
            let status = response.status();
            let headers = response
                .headers()
                .iter()
                .map(|(name, value)| {
                    (
                        name.as_str().to_owned(),
                        value.to_str().unwrap_or_default().to_owned(),
                    )
                })
                .collect();
            // Sınırı bir bayt aşınca okuma durur; HTTP katmanı `response_too_large` döner.
            let mut bytes = Vec::new();
            while bytes.len() <= MAX_RESPONSE_BYTES {
                match response.chunk().await.map_err(|e| e.to_string())? {
                    Some(chunk) => bytes.extend_from_slice(&chunk),
                    None => break,
                }
            }
            bytes.truncate(MAX_RESPONSE_BYTES + 1);
            let body = String::from_utf8_lossy(&bytes).into_owned();
            Ok(HttpResponse {
                status: status.as_u16(),
                status_text: status.canonical_reason().unwrap_or_default().to_owned(),
                headers,
                body,
            })
        })
    }
}

pub(crate) enum Auth {
    ApiKey(String),
    /// OAuth belirteç uçları: kimlik bilgisi gövdede, Authorization başlığı yok.
    None,
    Connection(Arc<TokenManager>),
}

pub(crate) struct HttpConfig {
    pub base_url: String,
    pub transport: Arc<dyn Transport>,
    pub max_retries: u32,
    pub timeout: Duration,
    /// Kullanımdan kaldırma uyarısı istemci örneği başına bir kez basılır.
    pub deprecation_warned: AtomicBool,
}

/// `Deprecation` başlığı varsa Türkçe uyarı metni (`Sunset` ve `Link` adresi eklenir).
pub(crate) fn deprecation_message(headers: &[(String, String)]) -> Option<String> {
    find_header(headers, "deprecation")?;
    let mut message = format!(
        "[nafru] Bu SDK sürümü (rust {}) kullanımdan kaldırıldı; lütfen güncelleyin.",
        crate::SDK_VERSION
    );
    if let Some(sunset) = find_header(headers, "sunset") {
        message.push_str(&format!(" Son tarih: {sunset}"));
    }
    if let Some(link) = find_header(headers, "link") {
        let url = link
            .split_once('<')
            .and_then(|(_, rest)| rest.split_once('>'))
            .map_or(link, |(url, _)| url);
        message.push_str(&format!(" Ayrıntı: {url}"));
    }
    Some(message)
}

#[derive(Clone)]
pub(crate) struct Http {
    config: Arc<HttpConfig>,
    auth: Arc<Auth>,
}

pub(crate) struct Req<'a> {
    pub method: &'static str,
    pub path: String,
    pub query: Vec<(String, String)>,
    pub body: Option<Value>,
    /// `Idempotency-Key` başlığı (olay uçları tekrarı yok sayar).
    pub idempotency_key: Option<&'a str>,
}

impl Req<'_> {
    pub fn new(method: &'static str, path: String) -> Self {
        Self {
            method,
            path,
            query: Vec::new(),
            body: None,
            idempotency_key: None,
        }
    }

    pub fn body(mut self, body: &impl Serialize) -> Self {
        self.body = Some(
            serde_json::to_value(body).expect("SDK gövde türleri her zaman JSON'a çevrilebilir"),
        );
        self
    }

    pub fn query(mut self, query: &impl Serialize) -> Self {
        self.query = query_pairs(query);
        self
    }
}

/// Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) `encodeURIComponent` gibi kaçırılır.
pub(crate) fn seg(value: &str) -> String {
    let mut out = String::with_capacity(value.len());
    for byte in value.bytes() {
        if byte.is_ascii_alphanumeric() || b"-_.!~*'()".contains(&byte) {
            out.push(byte as char);
        } else {
            out.push_str(&format!("%{byte:02X}"));
        }
    }
    out
}

/// Sorgu yalnız dolu değerleri taşır (`None` ve boş metin atlanır).
pub(crate) fn query_pairs(query: &impl Serialize) -> Vec<(String, String)> {
    let Ok(Value::Object(map)) = serde_json::to_value(query) else {
        return Vec::new();
    };
    map.into_iter()
        .filter_map(|(key, value)| match value {
            Value::Null => None,
            Value::String(text) if text.is_empty() => None,
            Value::String(text) => Some((key, text)),
            other => Some((key, other.to_string())),
        })
        .collect()
}

/// İstek gönderilmeden reddedilir: boş, `.` ya da `..` yol parçası URL normalleştirmesinde başka bir uca gider;
/// denetim karakteri taşıyan `Idempotency-Key` başlık enjeksiyonudur.
fn validate(req: &Req<'_>) -> Result<()> {
    let path = req.path.strip_prefix('/').unwrap_or(&req.path);
    if path
        .split('/')
        .any(|segment| matches!(segment, "" | "." | ".."))
    {
        return Err(NafruError::invalid(
            "Nafru SDK: kimlik boş, '.' ya da '..' olamaz",
        ));
    }
    if let Some(key) = req.idempotency_key
        && (key.is_empty() || key.chars().any(char::is_control))
    {
        return Err(NafruError::invalid(
            "Nafru SDK: idempotencyKey boş olamaz ve denetim karakteri (CR, LF, …) içeremez",
        ));
    }
    Ok(())
}

const BASE_BACKOFF_MS: u64 = 300;
const MAX_BACKOFF_MS: u64 = 8000;

fn backoff(attempt: u32) -> Duration {
    Duration::from_millis(
        BASE_BACKOFF_MS
            .saturating_mul(1 << attempt.min(16))
            .min(MAX_BACKOFF_MS),
    )
}

/// Kimlik bilgisi basılmaz; yalnız adres ve kimlik türü.
impl std::fmt::Debug for Http {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        let auth = match &*self.auth {
            Auth::ApiKey(_) => "api_key [REDACTED]",
            Auth::None => "none",
            Auth::Connection(_) => "connection [REDACTED]",
        };
        f.debug_struct("Http")
            .field("base_url", &self.config.base_url)
            .field("auth", &auth)
            .field("max_retries", &self.config.max_retries)
            .field("timeout", &self.config.timeout)
            .finish()
    }
}

impl Http {
    pub fn new(config: Arc<HttpConfig>, auth: Auth) -> Self {
        Self {
            config,
            auth: Arc::new(auth),
        }
    }

    pub async fn request<T: DeserializeOwned>(&self, req: Req<'_>) -> Result<T> {
        validate(&req)?;
        let (first, token) = self.attempts(&req).await;
        let value = match (first, &*self.auth, token) {
            // Süresi dolmuş / yenilenmiş belirteç: bir kez yenileyip tekrar dener.
            (Err(error), Auth::Connection(tokens), Some(stale))
                if error.name == "invalid_token" =>
            {
                tokens.invalidate(&stale).await?;
                self.attempts(&req).await.0?
            }
            (result, _, _) => result?,
        };
        serde_json::from_value(value)
            .map_err(|e| NafruError::network(format!("Yanıt çözümlenemedi: {e}")))
    }

    /// `GET` ve `DELETE` yinelenebilir; `POST`/`PATCH` yalnız istek işlenmeden reddedildiyse (429) ya da `Idempotency-Key`
    /// taşıyorsa yinelenir: anahtarsız sunucu hatasında e-posta çift gidebilir. Son kullanılan bağlantı belirtecini de döner.
    async fn attempts(&self, req: &Req<'_>) -> (Result<Value>, Option<String>) {
        let config = &self.config;
        let safe = matches!(req.method, "GET" | "DELETE") || req.idempotency_key.is_some();
        let mut url = format!("{}{}", config.base_url.trim_end_matches('/'), req.path);
        if !req.query.is_empty() {
            url.push('?');
            url.push_str(
                &url::form_urlencoded::Serializer::new(String::new())
                    .extend_pairs(&req.query)
                    .finish(),
            );
        }
        let mut headers = vec![
            ("accept".to_owned(), "application/json".to_owned()),
            ("user-agent".to_owned(), crate::USER_AGENT.to_owned()),
        ];
        let body = req.body.as_ref().map(|value| {
            headers.push(("content-type".to_owned(), "application/json".to_owned()));
            value.to_string()
        });
        if let Some(key) = req.idempotency_key {
            headers.push(("idempotency-key".to_owned(), key.to_owned()));
        }
        let mut current = None;

        for attempt in 0.. {
            let mut request_headers = headers.clone();
            match &*self.auth {
                Auth::ApiKey(key) => {
                    request_headers.push(("authorization".to_owned(), format!("Bearer {key}")))
                }
                Auth::None => {}
                Auth::Connection(tokens) => match tokens.access_token().await {
                    Ok(token) => {
                        request_headers
                            .push(("authorization".to_owned(), format!("Bearer {token}")));
                        current = Some(token);
                    }
                    Err(error) => return (Err(error), current),
                },
            }
            let last = attempt >= config.max_retries;
            let request = HttpRequest {
                method: req.method,
                url: url.clone(),
                headers: request_headers,
                body: body.clone(),
            };

            let response =
                match tokio::time::timeout(config.timeout, config.transport.send(request)).await {
                    Ok(Ok(response)) => response,
                    outcome => {
                        if !last && safe {
                            tokio::time::sleep(backoff(attempt)).await;
                            continue;
                        }
                        let error = match outcome {
                            Ok(Err(message)) => NafruError::network(message),
                            _ => NafruError::timeout(config.timeout.as_millis()),
                        };
                        return (Err(error), current);
                    }
                };

            if let Some(message) = deprecation_message(&response.headers)
                && !config.deprecation_warned.swap(true, Ordering::Relaxed)
            {
                eprintln!("{message}");
            }
            if response.body.len() > MAX_RESPONSE_BYTES {
                let error = NafruError::new(
                    Some(response.status),
                    "response_too_large",
                    format!("Yanıt gövdesi {MAX_RESPONSE_BYTES} baytı aşıyor"),
                );
                return (Err(error), current);
            }
            // API yönlendirmez; yönlendirme izlenmez ve yinelenmez (kimlik başka sunucuya gitmesin).
            if (300..400).contains(&response.status) {
                let error = NafruError::new(
                    Some(response.status),
                    "unexpected_redirect",
                    format!(
                        "Beklenmeyen yönlendirme (HTTP {}); izlenmedi",
                        response.status
                    ),
                );
                return (Err(error), current);
            }
            // Bozuk ya da boş gövde `null` sayılır (ara katman HTML'i).
            let payload = serde_json::from_str::<Value>(&response.body).unwrap_or(Value::Null);
            if (200..300).contains(&response.status) {
                return (Ok(payload), current);
            }
            let retry_after = find_header(&response.headers, "retry-after")
                .and_then(|v| v.trim().parse::<u64>().ok());
            let error = parse_error(
                response.status,
                &response.status_text,
                retry_after,
                &payload,
            );
            let retryable = response.status == 429 || (response.status >= 500 && safe);
            if retryable && !last {
                let wait = retry_after.map_or(backoff(attempt), Duration::from_secs);
                tokio::time::sleep(wait.min(Duration::from_millis(MAX_BACKOFF_MS))).await;
                continue;
            }
            return (Err(error), current);
        }
        unreachable!("deneme döngüsü her yolda döner")
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn h(pairs: &[(&str, &str)]) -> Vec<(String, String)> {
        pairs
            .iter()
            .map(|(k, v)| (k.to_string(), v.to_string()))
            .collect()
    }

    #[test]
    fn deprecation_message_includes_sunset_and_link() {
        assert_eq!(
            deprecation_message(&h(&[("content-type", "application/json")])),
            None
        );
        let message = deprecation_message(&h(&[
            ("Deprecation", "true"),
            ("Sunset", "Wed, 01 Jul 2027 00:00:00 GMT"),
            ("Link", "<https://nafru.com/sdk>; rel=\"deprecation\""),
        ]))
        .unwrap();
        assert_eq!(
            message,
            format!(
                "[nafru] Bu SDK sürümü (rust {}) kullanımdan kaldırıldı; lütfen güncelleyin. Son tarih: Wed, 01 Jul 2027 00:00:00 GMT Ayrıntı: https://nafru.com/sdk",
                crate::SDK_VERSION
            )
        );
    }
}
