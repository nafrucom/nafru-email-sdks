package com.nafru.email;

import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.JsonNode;
import java.io.IOException;
import java.net.URLEncoder;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.LinkedHashMap;
import java.util.Map;
import java.util.StringJoiner;
import java.util.function.Supplier;

/** Kimlik, JSON gövde, yeniden deneme ve hata ayrıştırmalı istek katmanı. */
final class Http {
    private static final long MAX_BACKOFF_MS = 8000;
    private static final long BASE_BACKOFF_MS = 300;
    /** Yanıt gövdesi üst sınırı: bozuk ya da kötü niyetli bir ara katman belleği tüketemesin. */
    static final int MAX_RESPONSE_BYTES = 10 * 1024 * 1024;

    /** Bir istek; {@code query} ve {@code body} {@code null} olabilir. */
    record Request(String method, String path, Map<String, ?> query, Object body, String idempotencyKey) {
        static Request get(String path, Map<String, ?> query) { return new Request("GET", path, query, null, null); }
        static Request get(String path) { return get(path, null); }
        static Request delete(String path) { return new Request("DELETE", path, null, null, null); }
        static Request post(String path, Object body) { return new Request("POST", path, null, body, null); }
        static Request post(String path, Object body, String key) { return new Request("POST", path, null, body, key); }
        static Request patch(String path, Object body) { return new Request("PATCH", path, null, body, null); }
        static Request put(String path, Object body) { return new Request("PUT", path, null, body, null); }
    }

    /** Kaynakların çağırdığı arayüz: bağlantı istemcisi kimlik yönetimini bunun arkasına koyar. */
    interface Caller {
        <T> T call(Request request, JavaType type);

        default <T> T call(Request request, Class<T> type) {
            return call(request, Json.MAPPER.constructType(type));
        }
    }

    private final String base;
    private final Transport transport;
    private final int maxRetries;
    private final Duration timeout;
    private final String userAgent;
    private final java.util.concurrent.atomic.AtomicBoolean deprecationWarned = new java.util.concurrent.atomic.AtomicBoolean();

    Http(String baseUrl, Transport transport, int maxRetries, Duration timeout, String userAgent) {
        this.base = baseUrl.replaceAll("/+$", "");
        this.transport = transport;
        this.maxRetries = maxRetries;
        this.timeout = timeout;
        this.userAgent = userAgent;
    }

    /** Sabit belirteçli çağırıcı ({@code null}: Authorization başlığı yok). */
    Caller caller(String token) {
        return new Caller() {
            @Override
            public <T> T call(Request request, JavaType type) {
                return Http.this.request(request, () -> token, type);
            }
        };
    }

    static String serializeQuery(Map<String, ?> query) {
        if (query == null) return "";
        StringJoiner joiner = new StringJoiner("&");
        query.forEach((key, value) -> {
            if (value != null && !"".equals(value)) joiner.add(form(key) + "=" + form(String.valueOf(value)));
        });
        return joiner.length() == 0 ? "" : "?" + joiner;
    }

    private static String form(String value) {
        return URLEncoder.encode(value, StandardCharsets.UTF_8);
    }

    /** Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) güvenle kaçırılır. */
    static String seg(String value) {
        // Boş, "." ve ".." URL normalleştirmesiyle başka bir uca gider; istek atılmadan reddedilir.
        if (value == null || value.isEmpty() || value.equals(".") || value.equals("..")) {
            throw invalidArgument("Geçersiz yol parçası: boş, \".\" ya da \"..\" olamaz");
        }
        return URLEncoder.encode(value, StandardCharsets.UTF_8).replace("+", "%20");
    }

    static NafruException invalidArgument(String message) {
        return new NafruException(null, "invalid_argument", message);
    }

    /**
     * API anahtarı ya da belirteç düz HTTP'de sızmasın: yalnız https; http yalnız yerel geliştirme adreslerinde
     * ({@code localhost}, {@code *.localhost}, {@code 127.0.0.0/8}, {@code [::1]}).
     */
    static String requireSecureUrl(String url, String field) {
        java.net.URI uri;
        try {
            uri = java.net.URI.create(url);
        } catch (IllegalArgumentException e) {
            throw new IllegalArgumentException("Nafru SDK: " + field + " geçerli bir adres değil", e);
        }
        String scheme = uri.getScheme() == null ? "" : uri.getScheme().toLowerCase(java.util.Locale.ROOT);
        String host = uri.getHost() == null ? "" : uri.getHost().toLowerCase(java.util.Locale.ROOT);
        boolean loopback = host.equals("localhost") || host.endsWith(".localhost") || host.equals("[::1]")
                || host.matches("127(\\.\\d{1,3}){3}");
        if (scheme.equals("https") && !host.isEmpty()) return url;
        if (scheme.equals("http") && loopback) return url;
        throw new IllegalArgumentException("Nafru SDK: " + field + " https kullanmalı (http yalnız localhost için)");
    }

    /**
     * {@code GET} ve {@code DELETE} yinelenebilir; {@code POST}/{@code PATCH} yalnız istek işlenmeden reddedildiyse (429) ya da
     * {@code Idempotency-Key} taşıyorsa yinelenir: anahtarsız sunucu hatasında e-posta çift gidebilir.
     */
    private static boolean isSafeToRetry(Request request) {
        return request.method().equals("GET") || request.method().equals("DELETE") || request.idempotencyKey() != null;
    }

    /** {@code authorize} her denemede çağrılır; {@code null} dönerse Authorization başlığı gönderilmez, hata fırlatırsa istek gitmez. */
    <T> T request(Request request, Supplier<String> authorize, JavaType type) {
        Map<String, String> headers = new LinkedHashMap<>();
        headers.put("accept", "application/json");
        headers.put("user-agent", userAgent);
        String body = null;
        if (request.body() != null) {
            body = Json.write(request.body());
            headers.put("content-type", "application/json");
        }
        if (request.idempotencyKey() != null) {
            // Başlık enjeksiyonu: CR/LF ve diğer denetim karakterleri başlığa giremez.
            if (request.idempotencyKey().isEmpty()
                    || request.idempotencyKey().chars().anyMatch(c -> c < 0x20 || c == 0x7f)) {
                throw invalidArgument("Geçersiz idempotencyKey: boş olamaz, denetim karakteri içeremez");
            }
            headers.put("idempotency-key", request.idempotencyKey());
        }
        String url = base + request.path() + serializeQuery(request.query());

        for (int attempt = 0; ; attempt++) {
            String token = authorize.get();
            if (token == null) headers.remove("authorization");
            else headers.put("authorization", "Bearer " + token);
            boolean last = attempt >= maxRetries;

            Transport.Response response;
            try {
                response = transport.send(new Transport.Request(request.method(), url, Map.copyOf(headers), body, timeout));
            } catch (InterruptedException e) {
                Thread.currentThread().interrupt();
                throw NafruException.network("İstek iptal edildi");
            } catch (IOException e) {
                if (!last && isSafeToRetry(request)) {
                    sleep(Math.min(BASE_BACKOFF_MS << Math.min(attempt, 20), MAX_BACKOFF_MS));
                    continue;
                }
                if (e instanceof HttpTimeoutException) throw NafruException.timeout(timeout.toMillis());
                throw NafruException.network(e.getMessage() != null ? e.getMessage() : "Sunucuya ulaşılamadı");
            }

            warnIfDeprecated(response);
            String text = response.body();
            if (text != null && text.length() > MAX_RESPONSE_BYTES) throw responseTooLarge(response.status());
            if (response.status() >= 300 && response.status() < 400) {
                // API yönlendirmez; izlemek Authorization başlığını başka bir sunucuya sızdırabilir. Yinelenmez.
                throw new NafruException(response.status(), "unexpected_redirect",
                        "Beklenmeyen yönlendirme (HTTP " + response.status() + ") reddedildi");
            }
            if (response.status() >= 200 && response.status() < 300) {
                return text == null || text.isBlank() ? null : Json.read(text, type);
            }

            NafruException error = parseError(response);
            boolean retryable = response.status() == 429 || (response.status() >= 500 && isSafeToRetry(request));
            if (retryable && !last) {
                double wait = error.getRetryAfter() != null
                        ? error.getRetryAfter() * 1000
                        : BASE_BACKOFF_MS << Math.min(attempt, 20);
                sleep((long) Math.min(wait, MAX_BACKOFF_MS));
                continue;
            }
            throw error;
        }
    }

    /** Sunucu bu SDK sürümünü kullanımdan kaldırdıysa istemci başına bir kez uyarır; çağrıyı asla bozmaz. */
    private void warnIfDeprecated(Transport.Response response) {
        if (response.header("deprecation") == null || !deprecationWarned.compareAndSet(false, true)) return;
        StringBuilder message = new StringBuilder("[nafru] Bu SDK sürümü (java " + NafruEmail.SDK_VERSION
                + ") kullanımdan kaldırıldı; lütfen güncelleyin.");
        String sunset = response.header("sunset");
        if (sunset != null) message.append(" Son tarih: ").append(sunset);
        String link = response.header("link");
        if (link != null) {
            java.util.regex.Matcher url = java.util.regex.Pattern.compile("<([^>]*)>").matcher(link);
            message.append(" Ayrıntı: ").append(url.find() ? url.group(1) : link.trim());
        }
        System.err.println(message);
    }

    static NafruException responseTooLarge(Integer status) {
        return new NafruException(status, "response_too_large", "Yanıt gövdesi " + MAX_RESPONSE_BYTES + " baytı aşıyor");
    }

    private static void sleep(long ms) {
        try {
            Thread.sleep(ms);
        } catch (InterruptedException e) {
            Thread.currentThread().interrupt();
            throw NafruException.network("İstek iptal edildi");
        }
    }

    private static Double readRetryAfter(Transport.Response response) {
        String header = response.header("retry-after");
        if (header == null) return null;
        try {
            double value = Double.parseDouble(header.trim());
            return Double.isFinite(value) && value >= 0 ? value : null;
        } catch (NumberFormatException e) {
            return null; // HTTP tarihi biçimi: üstel bekleme kullanılır.
        }
    }

    /** Standart gövde ({@code statusCode}, {@code name}, {@code message}, {@code errors}) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde). */
    static NafruException parseError(Transport.Response response) {
        Double retryAfter = readRetryAfter(response);
        int status = response.status();
        JsonNode body = null;
        try {
            if (response.body() != null && !response.body().isBlank()) body = Json.MAPPER.readTree(response.body());
        } catch (IOException ignored) {
            // JSON olmayan gövde: durumdan kurulur.
        }
        if (body != null && body.isObject() && body.path("message").isTextual()) {
            java.util.List<FieldError> errors = new java.util.ArrayList<>();
            if (body.path("errors").isArray()) {
                for (JsonNode entry : body.get("errors")) {
                    if (!entry.isObject()) continue;
                    errors.add(new FieldError(
                            entry.path("field").isTextual() ? entry.get("field").asText() : "",
                            entry.path("message").isTextual() ? entry.get("message").asText() : "",
                            entry.path("i18nTranslationKey").isTextual() ? entry.get("i18nTranslationKey").asText() : null));
                }
            }
            return new NafruException(
                    body.path("statusCode").isNumber() ? body.get("statusCode").asInt() : status,
                    body.path("name").isTextual() ? body.get("name").asText() : NafruException.nameForStatus(status),
                    body.get("message").asText(),
                    errors,
                    retryAfter);
        }
        return new NafruException(status, NafruException.nameForStatus(status), "HTTP " + status, null, retryAfter);
    }
}
