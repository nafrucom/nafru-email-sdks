//! Nafru Email için resmi Rust SDK'sı.
//!
//! ```no_run
//! # async fn f() -> nafru_email::Result<()> {
//! use nafru_email::{NafruEmail, SendEmailInput, SendEmailOptions};
//! let nafru = NafruEmail::new("nafru_…")?; // boş anahtar: NAFRU_API_KEY
//! let sent = nafru
//!     .emails
//!     .send(
//!         &SendEmailInput {
//!             from: Some("Acme <merhaba@ornek.com>".into()),
//!             to: vec!["ali@example.org".into()],
//!             subject: Some("Hoş geldin".into()),
//!             html: Some("<p>Merhaba!</p>".into()),
//!             ..Default::default()
//!         },
//!         SendEmailOptions::idempotency_key("kayit-1042"),
//!     )
//!     .await?;
//! println!("{}", sent.id);
//! # Ok(()) }
//! ```

/// `Debug`: gizli alanlar `[REDACTED]` basılır (anahtar, belirteç, imza sırrı günlüğe düşmesin).
macro_rules! redacted_debug {
    ($name:ty { $($field:ident),* } secret { $($secret:ident),* }) => {
        impl std::fmt::Debug for $name {
            fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
                f.debug_struct(stringify!($name))
                    $(.field(stringify!($field), &self.$field))*
                    $(.field(stringify!($secret), &crate::REDACTED))*
                    .finish()
            }
        }
    };
}

mod app;
mod dev_outbox;
mod error;
mod http;
mod pagination;
mod resources;
pub mod types;
mod webhook;

pub use app::{
    Connection, ConnectionEmails, ConnectionOptions, ConnectionSendersResource,
    ConnectionTemplatesResource, NafruConnect, NafruConnectOptions, create_pkce,
};
pub use dev_outbox::DevOutbox;
pub use error::{NafruError, NafruFieldError, Result};
pub use http::{BoxFuture, HttpRequest, HttpResponse, ReqwestTransport, Transport};
pub use pagination::{PageQuery, Paginator, paginate};
pub use resources::*;
pub use types::*;
pub use webhook::{VerifyWebhookInput, verify_webhook};

use http::{Auth, Http, HttpConfig};
use std::sync::Arc;
use std::sync::atomic::AtomicBool;
use std::time::Duration;

/// SDK sürümü: tek kaynak `Cargo.toml` içindeki `version`.
pub const SDK_VERSION: &str = env!("CARGO_PKG_VERSION");
pub(crate) const USER_AGENT: &str = concat!("nafru-email-rust/", env!("CARGO_PKG_VERSION"));

#[derive(Clone, Default)]
pub struct NafruEmailOptions {
    /// Dashboard'dan üretilen API anahtarı; boşsa `NAFRU_API_KEY` ortam değişkeni. İstemciye gömmeyin; `sending_access`
    /// anahtarı bile e-posta gönderebilir.
    pub api_key: String,
    /// API'nin kök adresi; boşsa `DEFAULT_BASE_URL` (yerelde `http://localhost:48787/api`).
    pub base_url: String,
    /// Özel taşıyıcı (test, proxy); varsayılan `reqwest`.
    pub transport: Option<Arc<dyn Transport>>,
    /// `429` ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme sayısı; varsayılan 2, `Some(0)` kapatır.
    pub max_retries: Option<u32>,
    /// İstek başına zaman aşımı; varsayılan 30 sn.
    pub timeout: Option<Duration>,
    /// Varsayılan: `NODE_ENV=development` iken `.nafru/emails`, aksi hâlde kapalı; `DevOutbox::Off` her zaman gerçek gönderim.
    pub dev_outbox: DevOutbox,
}

/// Gizli değerlerin (`api_key`, belirteçler, `client_secret`) `Debug` çıktısındaki yerine geçen metin.
pub const REDACTED: &str = "[REDACTED]";

/// Nafru Email üretim API'si; `base_url` boşsa kullanılır.
pub const DEFAULT_BASE_URL: &str = "https://email.nafru.com/api";

pub(crate) fn effective_base_url(base_url: String) -> String {
    if base_url.is_empty() {
        DEFAULT_BASE_URL.to_owned()
    } else {
        base_url
    }
}

/// Yalnız `https`; `http` yalnız yerel geliştirme için (`localhost`, `*.localhost`, `127.0.0.0/8`, `[::1]`):
/// düz `http` API anahtarını ve belirteçleri ağda açık taşır.
pub(crate) fn require_https(value: &str, label: &str) -> Result<()> {
    let error = || {
        NafruError::invalid(format!(
            "Nafru SDK: {label} https kullanmalı (http yalnız localhost için)"
        ))
    };
    let url = url::Url::parse(value).map_err(|_| error())?;
    let local = match url.host() {
        Some(url::Host::Domain(host)) => host == "localhost" || host.ends_with(".localhost"),
        Some(url::Host::Ipv4(ip)) => ip.is_loopback(),
        Some(url::Host::Ipv6(ip)) => ip.is_loopback(),
        None => false,
    };
    match url.scheme() {
        "https" => Ok(()),
        "http" if local => Ok(()),
        _ => Err(error()),
    }
}

pub(crate) fn http_config(
    base_url: String,
    transport: Option<Arc<dyn Transport>>,
    max_retries: Option<u32>,
    timeout: Option<Duration>,
) -> Arc<HttpConfig> {
    Arc::new(HttpConfig {
        base_url,
        transport: transport.unwrap_or_else(|| Arc::new(ReqwestTransport::default())),
        max_retries: max_retries.unwrap_or(2),
        timeout: timeout.unwrap_or(Duration::from_secs(30)),
        deprecation_warned: AtomicBool::new(false),
    })
}

impl NafruEmail {
    /// API anahtarıyla istemci (Resend'deki `new Resend('re_…')` gibi); boş anahtar `NAFRU_API_KEY`'den okunur.
    pub fn new(api_key: impl Into<String>) -> Result<Self> {
        Self::with_options(NafruEmailOptions {
            api_key: api_key.into(),
            ..Default::default()
        })
    }

    /// Ayarlı istemci: `base_url`, `transport`, `max_retries`, `timeout`, `dev_outbox` isteğe bağlıdır.
    pub fn with_options(mut options: NafruEmailOptions) -> Result<Self> {
        if options.api_key.is_empty() {
            options.api_key = std::env::var("NAFRU_API_KEY").unwrap_or_default();
        }
        if options.api_key.is_empty() {
            return Err(NafruError::invalid("Nafru SDK: apiKey gerekli"));
        }
        let base_url = effective_base_url(options.base_url);
        require_https(&base_url, "baseUrl")?;
        let config = http_config(
            base_url,
            options.transport,
            options.max_retries,
            options.timeout,
        );
        Ok(resources::build(
            Http::new(config, Auth::ApiKey(options.api_key)),
            options.dev_outbox.resolve(),
        ))
    }
}

redacted_debug!(NafruEmailOptions { base_url, max_retries, timeout, dev_outbox } secret { api_key });
