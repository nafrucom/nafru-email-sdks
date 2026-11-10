package com.nafru.email;

import com.nafru.email.model.AuthorizeUrl;
import com.nafru.email.model.AuthorizeUrlInput;
import com.nafru.email.model.ConnectionGrant;
import com.nafru.email.model.ExchangeInput;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.security.NoSuchAlgorithmException;
import java.security.SecureRandom;
import java.time.Duration;
import java.util.Base64;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.StringJoiner;

/**
 * "Nafru ile bağlan": müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir. API anahtarı kopyalama yoktur.
 * Tek hesap ve API anahtarı için {@link NafruEmail} kullanın.
 */
public final class NafruConnect {
    private static final SecureRandom RANDOM = new SecureRandom();

    private final String clientId;
    private final String clientSecret;
    private final String webUrl;
    private final Http http;
    private final Http.Caller oauth;
    private final String devOutbox;

    private NafruConnect(Builder builder) {
        if (builder.clientId == null || builder.clientId.isEmpty()) throw new IllegalArgumentException("Nafru SDK: clientId gerekli");
        if (builder.clientSecret == null || builder.clientSecret.isEmpty()) throw new IllegalArgumentException("Nafru SDK: clientSecret gerekli");
        this.clientId = builder.clientId;
        this.clientSecret = builder.clientSecret;
        String baseUrl = NafruEmail.effectiveBaseUrl(builder.baseUrl);
        String web = builder.webUrl != null ? builder.webUrl : baseUrl.replaceAll("/api/*$", "");
        this.webUrl = Http.requireSecureUrl(web, "webUrl").replaceAll("/+$", "");
        this.http = new Http(baseUrl, builder.transport, builder.maxRetries, builder.timeout, NafruEmail.USER_AGENT);
        // Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        this.oauth = http.caller(null);
        this.devOutbox = DevOutbox.resolve(builder.devOutboxSet, builder.devOutbox, NafruEmail.env.apply("NODE_ENV"));
    }

    public static Builder builder() { return new Builder(); }

    /** İstemci gizlisi yazılmaz. */
    @Override
    public String toString() { return "NafruConnect[clientId=" + clientId + ", clientSecret=" + Redact.SECRET + "]"; }

    /** Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç {@code onTokenRefresh} ile gelir. */
    public NafruConnection connection(String connectionId, String refreshToken, TokenRefreshListener onTokenRefresh) {
        TokenManager tokens = new TokenManager(oauth, clientId, clientSecret, refreshToken, onTokenRefresh);
        return new NafruConnection(connectionId, http, tokens, devOutbox);
    }

    private static String base64Url(byte[] bytes) {
        return Base64.getUrlEncoder().withoutPadding().encodeToString(bytes);
    }

    /** PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması. */
    static String[] createPkce() {
        byte[] random = new byte[32];
        RANDOM.nextBytes(random);
        String verifier = base64Url(random);
        try {
            byte[] digest = MessageDigest.getInstance("SHA-256").digest(verifier.getBytes(StandardCharsets.US_ASCII));
            return new String[] {verifier, base64Url(digest)};
        } catch (NoSuchAlgorithmException e) {
            throw new IllegalStateException(e);
        }
    }

    /**
     * Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. {@code codeVerifier}'ı oturumda saklayın; dönüşte {@code exchange}'e
     * verin. Dönüşte {@code state}'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
     */
    public AuthorizeUrl authorizeUrl(AuthorizeUrlInput input) {
        if (input.state() == null || input.state().isEmpty()) {
            throw new IllegalArgumentException("Nafru SDK: state gerekli (CSRF koruması)");
        }
        if (input.scopes() == null || input.scopes().isEmpty()) {
            throw new IllegalArgumentException("Nafru SDK: en az bir izin (scopes) gerekli");
        }
        String[] pkce = createPkce();
        Map<String, String> params = new LinkedHashMap<>();
        params.put("client_id", clientId);
        params.put("redirect_uri", input.redirectUri());
        params.put("state", input.state());
        params.put("scope", String.join(" ", input.scopes()));
        params.put("code_challenge", pkce[1]);
        params.put("code_challenge_method", "S256");
        if (input.loginHint() != null && !input.loginHint().isEmpty()) params.put("login_hint", input.loginHint());
        StringJoiner query = new StringJoiner("&");
        params.forEach((key, value) -> query.add(key + "=" + URLEncoder.encode(value, StandardCharsets.UTF_8)));
        return new AuthorizeUrl(webUrl + "/connect?" + query, pkce[0]);
    }

    /** Dönüşteki tek kullanımlık {@code code}'u bağlantıya çevirir (sunucunuzdan çağırın). */
    public ConnectionGrant exchange(ExchangeInput input) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("grant_type", "authorization_code");
        body.put("client_id", clientId);
        body.put("client_secret", clientSecret);
        body.put("code", input.code());
        body.put("code_verifier", input.codeVerifier());
        body.put("redirect_uri", input.redirectUri());
        TokenManager.TokenPayload payload = oauth.call(Http.Request.post("/oauth/token", body), TokenManager.TokenPayload.class);
        return new ConnectionGrant(payload.connectionId(), payload.refreshToken(),
                payload.scopes() == null ? List.of() : payload.scopes());
    }

    /** Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur. */
    public void revoke(String refreshToken) {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("client_id", clientId);
        body.put("client_secret", clientSecret);
        body.put("token", refreshToken);
        oauth.call(Http.Request.post("/oauth/revoke", body), Object.class);
    }

    public static final class Builder {
        private String clientId;
        private String clientSecret;
        private String baseUrl;
        private String webUrl;
        private Transport transport = new HttpClientTransport();
        private int maxRetries = 2;
        private Duration timeout = Duration.ofSeconds(30);
        private String devOutbox;
        private boolean devOutboxSet;

        private Builder() {}

        /** Kayıtlı uygulamanın {@code app_…} kimliği (değişmez). */
        public Builder clientId(String clientId) { this.clientId = clientId; return this; }

        /** Yalnız sunucunuzda; istemci paketine girmez. */
        public Builder clientSecret(String clientSecret) { this.clientSecret = clientSecret; return this; }

        /** API'nin kök adresi; varsayılan {@link NafruEmail#DEFAULT_BASE_URL}. */
        public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }

        /** İzin ekranının (Nafru web uygulaması) kök adresi; verilmezse {@code baseUrl} sonundaki {@code /api} atılarak. */
        public Builder webUrl(String webUrl) { this.webUrl = webUrl; return this; }

        public Builder transport(Transport transport) { this.transport = transport; return this; }

        public Builder maxRetries(int maxRetries) { this.maxRetries = maxRetries; return this; }

        public Builder timeout(Duration timeout) { this.timeout = timeout; return this; }

        /** Dev çıkış kutusu: verilirse {@code connection(...).emails().send} gönderim yapmaz, e-postayı bu klasöre yazar. */
        public Builder devOutbox(String dir) { this.devOutbox = dir; this.devOutboxSet = true; return this; }

        public Builder devOutbox(boolean enabled) {
            return enabled ? devOutbox(DevOutbox.DEFAULT_DIR) : devOutbox((String) null);
        }

        public NafruConnect build() { return new NafruConnect(this); }
    }
}
