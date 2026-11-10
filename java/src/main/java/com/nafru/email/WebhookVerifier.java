package com.nafru.email;

import java.nio.charset.StandardCharsets;
import java.security.GeneralSecurityException;
import java.security.MessageDigest;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;

/**
 * Svix / Standard Webhooks uyumlu imza doğrulama.
 *
 * <pre>
 *   imzalanan  = svix-id + "." + svix-timestamp + "." + ham gövde
 *   anahtar    = whsec_ sonrası base64 çözülmüş signing_secret
 *   başlık     = v1,&lt;base64 HMAC-SHA256&gt; (anahtar döndürmede boşlukla ayrılmış birden çok imza)
 * </pre>
 */
public final class WebhookVerifier {
    private static final String SECRET_PREFIX = "whsec_";
    public static final long DEFAULT_TOLERANCE_SECONDS = 300;
    /** Anahtar döndürmede birden çok imza gelir; sınırsız liste işlemci tüketmesin. */
    private static final int MAX_SIGNATURES = 32;

    private WebhookVerifier() {}

    /** {@link #verify(String, String, String, String, String, long, long)} varsayılan tolerans ve şimdiki zamanla. */
    public static boolean verify(String payload, String id, String timestamp, String signature, String secret) {
        return verify(payload, id, timestamp, signature, secret, DEFAULT_TOLERANCE_SECONDS, System.currentTimeMillis());
    }

    /**
     * İmza ve zaman damgası geçerliyse {@code true}. Bozuk imza ya da zaman damgası {@code false}; bozuk {@code secret}
     * {@link IllegalArgumentException} fırlatır (yapılandırma hatası).
     *
     * @param payload HAM istek gövdesi: ayrıştırılıp yeniden dizilmiş JSON imzayı bozar
     * @param id {@code svix-id} başlığı
     * @param timestamp {@code svix-timestamp} başlığı
     * @param signature {@code svix-signature} başlığı
     * @param secret webhook'un {@code signing_secret} değeri ({@code whsec_…})
     * @param toleranceSeconds tekrar saldırısına karşı izin verilen zaman farkı
     * @param nowMillis şimdiki zaman (ms); testler için
     */
    public static boolean verify(
            String payload, String id, String timestamp, String signature, String secret, long toleranceSeconds, long nowMillis) {
        if (secret == null || !secret.startsWith(SECRET_PREFIX)) {
            throw new IllegalArgumentException("Geçersiz imza anahtarı: whsec_ ile başlamalı");
        }
        byte[] key;
        try {
            key = Base64.getDecoder().decode(secret.substring(SECRET_PREFIX.length()));
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Geçersiz imza anahtarı: base64 çözülemedi", e);
        }
        if (payload == null || id == null || id.isEmpty() || timestamp == null || signature == null || signature.isEmpty()) return false;

        double sent;
        try {
            sent = Double.parseDouble(timestamp);
        } catch (NumberFormatException e) {
            return false;
        }
        long nowSeconds = Math.floorDiv(nowMillis, 1000);
        if (!Double.isFinite(sent) || Math.abs(nowSeconds - sent) > toleranceSeconds) return false;

        byte[] expected;
        try {
            Mac mac = Mac.getInstance("HmacSHA256");
            mac.init(new SecretKeySpec(key, "HmacSHA256"));
            expected = mac.doFinal((id + "." + timestamp + "." + payload).getBytes(StandardCharsets.UTF_8));
        } catch (GeneralSecurityException | IllegalArgumentException e) {
            throw new IllegalArgumentException("Geçersiz imza anahtarı: " + e.getMessage(), e);
        }

        String[] candidates = signature.split(" ");
        for (int index = 0; index < Math.min(candidates.length, MAX_SIGNATURES); index++) {
            String candidate = candidates[index];
            String[] parts = candidate.split(",", 2);
            if (parts.length != 2 || !parts[0].equals("v1") || parts[1].isEmpty()) continue;
            byte[] given;
            try {
                given = Base64.getDecoder().decode(parts[1]);
            } catch (IllegalArgumentException e) {
                continue;
            }
            // Sabit zamanlı karşılaştırma.
            if (MessageDigest.isEqual(expected, given)) return true;
        }
        return false;
    }
}
