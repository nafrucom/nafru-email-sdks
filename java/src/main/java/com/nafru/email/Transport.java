package com.nafru.email;

import java.io.IOException;
import java.time.Duration;
import java.util.Map;

/**
 * HTTP taşıyıcısı: varsayılanı {@link java.net.http.HttpClient}; test, proxy ya da kendi istemciniz için değiştirin. Zaman aşımını
 * {@link java.net.http.HttpTimeoutException} ile, diğer ağ hatalarını {@link IOException} ile bildirin.
 */
@FunctionalInterface
public interface Transport {
    Response send(Request request) throws IOException, InterruptedException;

    /** {@code body} gövdesiz istekte {@code null}; başlık adları küçük harf. */
    record Request(String method, String url, Map<String, String> headers, String body, Duration timeout) {
        /** Authorization ve gövde (OAuth istemci gizlisi, belirteçler) yazılmaz. */
        @Override
        public String toString() {
            return "Request[method=" + method + ", url=" + url + ", headers=" + (headers == null ? null : headers.keySet())
                    + ", body=" + (body == null ? null : Redact.SECRET) + ", timeout=" + timeout + "]";
        }
    }

    /** {@code headers} anahtarları küçük harf; {@code body} boş olabilir. */
    record Response(int status, Map<String, String> headers, String body) {
        public String header(String name) {
            return headers == null ? null : headers.get(name.toLowerCase(java.util.Locale.ROOT));
        }
    }
}
