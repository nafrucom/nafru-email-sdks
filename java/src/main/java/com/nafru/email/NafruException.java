package com.nafru.email;

import java.util.List;
import java.util.Map;

/**
 * Her başarısız çağrının hatası. {@code statusCode} ağ hatalarında {@code null}'dır. {@code name}, sunucunun hata adıdır
 * ({@code validation_error}, {@code rate_limit_exceeded}, {@code not_found}, …); ağ ve zaman aşımı için
 * {@code application_error} / {@code timeout_error}.
 */
public class NafruException extends RuntimeException {
    private static final Map<Integer, String> NAMES_BY_STATUS = Map.of(
            400, "invalid_request",
            401, "unauthorized",
            403, "forbidden",
            404, "not_found",
            409, "conflict",
            413, "payload_too_large",
            422, "validation_error",
            429, "rate_limit_exceeded");

    private final Integer statusCode;
    private final String name;
    private final List<FieldError> errors;
    private final Double retryAfter;

    public NafruException(Integer statusCode, String name, String message, List<FieldError> errors, Double retryAfter) {
        super(message);
        this.statusCode = statusCode;
        this.name = name;
        this.errors = errors == null ? List.of() : List.copyOf(errors);
        this.retryAfter = retryAfter;
    }

    public NafruException(Integer statusCode, String name, String message) {
        this(statusCode, name, message, null, null);
    }

    /** HTTP durumu; ağ hatası ve zaman aşımında {@code null}. */
    public Integer getStatusCode() { return statusCode; }

    public String getName() { return name; }

    /** 422'de alan ayrıntısı; yoksa boş liste. */
    public List<FieldError> getErrors() { return errors; }

    /** {@code 429} yanıtındaki {@code retry-after} (saniye); yoksa {@code null}. */
    public Double getRetryAfter() { return retryAfter; }

    static String nameForStatus(int status) {
        return NAMES_BY_STATUS.getOrDefault(status, "application_error");
    }

    static NafruException network(String message) {
        return new NafruException(null, "application_error", message);
    }

    static NafruException timeout(long timeoutMs) {
        return new NafruException(null, "timeout_error", "İstek " + timeoutMs + " ms içinde tamamlanmadı");
    }

    @Override
    public String toString() {
        return "NafruException{statusCode=" + statusCode + ", name=" + name + ", message=" + getMessage() + "}";
    }
}
