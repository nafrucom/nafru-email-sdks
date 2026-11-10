<?php

declare(strict_types=1);

namespace Nafru\Email;

/**
 * Svix / Standard Webhooks uyumlu imza doğrulama.
 *
 *   imzalanan  = "{svix-id}.{svix-timestamp}.{ham gövde}"
 *   anahtar    = `whsec_` sonrası base64 çözülmüş `signing_secret`
 *   başlık     = `v1,<base64 HMAC-SHA256>` (anahtar döndürmede boşlukla ayrılmış birden çok imza)
 */
final class Webhook
{
    private const SECRET_PREFIX = 'whsec_';

    /**
     * İmza ve zaman damgası geçerliyse `true`. Bozuk imza ya da zaman damgası `false`; bozuk `$secret` hata fırlatır (yapılandırma hatası).
     *
     * @param string $payload HAM istek gövdesi (`file_get_contents('php://input')`): ayrıştırılıp yeniden dizilmiş JSON imzayı bozar
     * @param array{id?: ?string, timestamp?: ?string, signature?: ?string} $headers eksik/boş başlık `false` döner; `svix-id`, `svix-timestamp`, `svix-signature`
     * @param string $secret webhook'un `signing_secret` değeri (`whsec_…`)
     * @param int $toleranceSeconds tekrar saldırısına karşı izin verilen zaman farkı
     * @param ?int $nowSeconds şimdiki zaman (Unix saniye); testler için
     */
    public static function verify(string $payload, array $headers, #[\SensitiveParameter] string $secret, int $toleranceSeconds = 300, ?int $nowSeconds = null): bool
    {
        if (!str_starts_with($secret, self::SECRET_PREFIX)) {
            throw new \InvalidArgumentException('Geçersiz imza anahtarı: whsec_ ile başlamalı');
        }
        $key = base64_decode(substr($secret, strlen(self::SECRET_PREFIX)), true);
        if ($key === false) {
            throw new \InvalidArgumentException('Geçersiz imza anahtarı: base64 çözülemedi');
        }

        $id = (string) ($headers['id'] ?? '');
        $timestamp = (string) ($headers['timestamp'] ?? '');
        $signature = (string) ($headers['signature'] ?? '');
        if ($id === '' || $signature === '') {
            return false;
        }
        $now = $nowSeconds ?? time();
        // Fark iki yönde de sınırlı (geçmiş ve gelecek).
        if (!ctype_digit($timestamp) || abs($now - (float) $timestamp) > $toleranceSeconds) {
            return false;
        }

        $expected = hash_hmac('sha256', "{$id}.{$timestamp}.{$payload}", $key, true);
        // Aşırı uzun başlık işlem yükü olmasın: ilk 32 imza.
        foreach (array_slice(explode(' ', $signature), 0, 32) as $candidate) {
            [$version, $value] = array_pad(explode(',', $candidate, 2), 2, '');
            if ($version !== 'v1' || $value === '') {
                continue;
            }
            $mac = base64_decode($value, true);
            // `hash_equals` sabit zamanlı karşılaştırır.
            if ($mac !== false && hash_equals($expected, $mac)) {
                return true;
            }
        }
        return false;
    }
}
