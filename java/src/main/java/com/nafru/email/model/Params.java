package com.nafru.email.model;

import com.fasterxml.jackson.annotation.JsonValue;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * İstek gövdesi ya da sorgusu. Alanlar API'deki {@code snake_case} adlarıyla bir haritada tutulur: çağrılmayan ayarlayıcı
 * gönderilmez, {@code null} ile çağrılan alan JSON'da açıkça {@code null} gider (sunucuda "temizle" anlamı taşır).
 */
public abstract class Params<S extends Params<S>> {
    private final Map<String, Object> values = new LinkedHashMap<>();

    @SuppressWarnings("unchecked")
    protected S set(String key, Object value) {
        values.put(key, value);
        return (S) this;
    }

    /** Tek adres ya da liste kabul eden alanlar (to, cc, bcc, reply_to): tek değer düz metin olarak gider. */
    protected S addresses(String key, String... value) {
        return set(key, value == null ? null : value.length == 1 ? value[0] : List.of(value));
    }

    /** Ham alan: SDK'nın henüz bilmediği bir alanı göndermek için. */
    public S put(String key, Object value) {
        return set(key, value);
    }

    @JsonValue
    public Map<String, Object> toMap() {
        return Collections.unmodifiableMap(values);
    }
}
