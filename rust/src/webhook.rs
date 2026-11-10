//! Svix / Standard Webhooks uyumlu imza doğrulama.
//!
//!   imzalanan  = `{svix-id}.{svix-timestamp}.{ham gövde}`
//!   anahtar    = `whsec_` sonrası base64 çözülmüş `signing_secret`
//!   başlık     = `v1,<base64 HMAC-SHA256>` (anahtar döndürmede boşlukla ayrılmış birden çok imza)

use crate::error::{NafruError, Result};
use base64::Engine;
use base64::engine::general_purpose::STANDARD_PAD_INDIFFERENT as BASE64;
use hmac::{Hmac, KeyInit, Mac};
use sha2::Sha256;
use std::time::{SystemTime, UNIX_EPOCH};

const SECRET_PREFIX: &str = "whsec_";
const MAX_SIGNATURES: usize = 32;
const DEFAULT_TOLERANCE_SECONDS: u64 = 300;

#[derive(Clone, Default)]
pub struct VerifyWebhookInput<'a> {
    /// HAM istek gövdesi (alındığı gibi, UTF-8): ayrıştırılıp yeniden dizilmiş JSON imzayı bozar.
    pub payload: &'a str,
    /// `svix-id` başlığı.
    pub id: &'a str,
    /// `svix-timestamp` başlığı.
    pub timestamp: &'a str,
    /// `svix-signature` başlığı.
    pub signature: &'a str,
    /// Webhook'un `signing_secret` değeri (`whsec_…`).
    pub secret: &'a str,
    /// Tekrar saldırısına karşı izin verilen zaman farkı (saniye); varsayılan 300.
    pub tolerance_seconds: Option<u64>,
    /// Şimdiki zaman (Unix saniyesi); testler için.
    pub now_seconds: Option<i64>,
}

/// İmza ve zaman damgası geçerliyse `Ok(true)`. Bozuk imza ya da zaman damgası `Ok(false)`; bozuk `secret` hata döner (yapılandırma hatası).
pub fn verify_webhook(input: &VerifyWebhookInput) -> Result<bool> {
    let encoded = input
        .secret
        .strip_prefix(SECRET_PREFIX)
        .ok_or_else(|| NafruError::invalid("Geçersiz imza anahtarı: whsec_ ile başlamalı"))?;
    let key = BASE64
        .decode(encoded)
        .map_err(|_| NafruError::invalid("Geçersiz imza anahtarı: base64 çözülemedi"))?;

    let Ok(timestamp) = input.timestamp.trim().parse::<i64>() else {
        return Ok(false);
    };
    let now = input.now_seconds.unwrap_or_else(|| {
        SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .map(|d| d.as_secs() as i64)
            .unwrap_or_default()
    });
    if now.abs_diff(timestamp) > input.tolerance_seconds.unwrap_or(DEFAULT_TOLERANCE_SECONDS) {
        return Ok(false);
    }

    let content = format!("{}.{}.{}", input.id, input.timestamp, input.payload);
    // Anahtar döndürmede birkaç imza gelir; sınırsız liste HMAC hesabıyla CPU tüketirdi.
    for candidate in input.signature.split(' ').take(MAX_SIGNATURES) {
        let Some(("v1", value)) = candidate.split_once(',') else {
            continue;
        };
        let Ok(signature) = BASE64.decode(value) else {
            continue;
        };
        let mut mac = Hmac::<Sha256>::new_from_slice(&key)
            .map_err(|_| NafruError::invalid("Geçersiz imza anahtarı"))?;
        mac.update(content.as_bytes());
        // `verify_slice` sabit zamanlı karşılaştırır.
        if mac.verify_slice(&signature).is_ok() {
            return Ok(true);
        }
    }
    Ok(false)
}

redacted_debug!(VerifyWebhookInput<'_> { payload, id, timestamp, signature, tolerance_seconds, now_seconds } secret { secret });
