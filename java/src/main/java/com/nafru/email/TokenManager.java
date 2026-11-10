package com.nafru.email;

import com.nafru.email.model.ConnectionTokens;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (kilit altında yenilenir, bekleyenler
 * yeni belirteci kullanır): dönüşlü yenileme belirteci ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı
 * iptal ettirirdi.
 */
final class TokenManager {
    /** Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı). */
    private static final long EARLY_REFRESH_MS = 30_000;

    record TokenPayload(String accessToken, String refreshToken, long expiresIn, String connectionId, List<String> scopes) {
        @Override
        public String toString() {
            return "TokenPayload[accessToken=" + Redact.mask(accessToken) + ", refreshToken=" + Redact.mask(refreshToken)
                    + ", expiresIn=" + expiresIn + ", connectionId=" + connectionId + ", scopes=" + scopes + "]";
        }
    }

    private final Http.Caller oauth;
    private final String clientId;
    private final String clientSecret;
    private final TokenRefreshListener listener;
    private String refreshToken;
    private String accessToken;
    private long expiresAt;
    /** Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı. */
    private boolean unpersisted;

    TokenManager(Http.Caller oauth, String clientId, String clientSecret, String refreshToken, TokenRefreshListener listener) {
        this.oauth = oauth;
        this.clientId = clientId;
        this.clientSecret = clientSecret;
        this.refreshToken = refreshToken;
        this.listener = listener;
    }

    private void persist() {
        try {
            listener.onTokenRefresh(new ConnectionTokens(refreshToken));
            unpersisted = false;
        } catch (Exception cause) {
            unpersisted = true;
            throw new NafruException(null, "token_persist_failed", "Yeni yenileme belirteci saklanamadı: " + cause.getMessage());
        }
    }

    private String refresh() {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("grant_type", "refresh_token");
        body.put("client_id", clientId);
        body.put("client_secret", clientSecret);
        body.put("refresh_token", refreshToken);
        TokenPayload payload;
        try {
            payload = oauth.call(Http.Request.post("/oauth/token", body), TokenPayload.class);
        } catch (NafruException error) {
            // Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
            String name = error.getName();
            Integer status = error.getStatusCode();
            if (name.equals("invalid_grant") || name.equals("connection_revoked")
                    || (status != null && status == 403 && !name.equals("rate_limit_exceeded"))) {
                throw new NafruException(status, "connection_revoked",
                        "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir.",
                        error.getErrors(), error.getRetryAfter());
            }
            throw error;
        }
        refreshToken = payload.refreshToken();
        accessToken = payload.accessToken();
        expiresAt = System.currentTimeMillis() + payload.expiresIn() * 1000;
        persist();
        return accessToken;
    }

    /** Geçerli erişim belirteci; yoksa ya da dolmak üzereyse yeniler. */
    synchronized String accessToken() {
        if (unpersisted) persist();
        if (accessToken != null && System.currentTimeMillis() < expiresAt - EARLY_REFRESH_MS) return accessToken;
        return refresh();
    }

    /** Sunucu 401 {@code invalid_token} dedi: eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır). */
    synchronized String invalidate(String stale) {
        if (stale.equals(accessToken)) accessToken = null;
        return accessToken != null ? accessToken : refresh();
    }

}
