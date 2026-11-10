package com.nafru.email;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.util.HashMap;
import java.util.Locale;
import java.util.Map;

/** {@link java.net.http.HttpClient} ile varsayılan taşıyıcı. */
public final class HttpClientTransport implements Transport {
    private final HttpClient client;

    public HttpClientTransport() {
        // Yönlendirme izlenmez: Authorization başka bir sunucuya gitmesin (3xx, unexpected_redirect olur).
        this(HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NEVER).build());
    }

    /** Kendi istemciniz yönlendirme izlememeli; izleyen istemci reddedilir. */
    public HttpClientTransport(HttpClient client) {
        if (client.followRedirects() != HttpClient.Redirect.NEVER) {
            throw new IllegalArgumentException("Nafru SDK: HttpClient yönlendirme izlememeli (Redirect.NEVER)");
        }
        this.client = client;
    }

    @Override
    public Response send(Request request) throws IOException, InterruptedException {
        HttpRequest.BodyPublisher body = request.body() == null
                ? HttpRequest.BodyPublishers.noBody()
                : HttpRequest.BodyPublishers.ofString(request.body());
        HttpRequest.Builder builder = HttpRequest.newBuilder(URI.create(request.url()))
                .method(request.method(), body)
                .timeout(request.timeout());
        // user-agent gibi kısıtlı başlıklar java.net.http'te serbest; yalnız host/content-length/connection yasak.
        request.headers().forEach(builder::header);
        HttpResponse<java.io.InputStream> response = client.send(builder.build(), HttpResponse.BodyHandlers.ofInputStream());
        Map<String, String> headers = new HashMap<>();
        response.headers().map().forEach((key, values) -> {
            if (!values.isEmpty()) headers.put(key.toLowerCase(Locale.ROOT), values.get(0));
        });
        return new Response(response.statusCode(), headers, readCapped(response));
    }

    /** Gövdeyi en çok {@link Http#MAX_RESPONSE_BYTES} okur; aşarsa {@code response_too_large}. */
    private static String readCapped(HttpResponse<java.io.InputStream> response) throws IOException {
        try (java.io.InputStream body = response.body()) {
            byte[] bytes = body.readNBytes(Http.MAX_RESPONSE_BYTES + 1);
            if (bytes.length > Http.MAX_RESPONSE_BYTES) throw Http.responseTooLarge(response.statusCode());
            return new String(bytes, java.nio.charset.StandardCharsets.UTF_8);
        }
    }
}
