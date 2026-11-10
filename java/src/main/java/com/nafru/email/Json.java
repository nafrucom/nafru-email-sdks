package com.nafru.email;

import com.fasterxml.jackson.annotation.JsonInclude;
import com.fasterxml.jackson.core.JsonProcessingException;
import com.fasterxml.jackson.databind.DeserializationFeature;
import com.fasterxml.jackson.databind.JavaType;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.PropertyNamingStrategies;

/** Kayıt alanları camelCase, ağda snake_case; bilinmeyen alanlar yok sayılır (sunucu yeni alan ekleyebilir). */
final class Json {
    static final ObjectMapper MAPPER = new ObjectMapper()
            .setPropertyNamingStrategy(PropertyNamingStrategies.SNAKE_CASE)
            .setDefaultPropertyInclusion(JsonInclude.Value.construct(JsonInclude.Include.NON_NULL, JsonInclude.Include.ALWAYS))
            .configure(DeserializationFeature.FAIL_ON_UNKNOWN_PROPERTIES, false);

    private Json() {}

    static JavaType listOf(Class<?> item) {
        return MAPPER.getTypeFactory().constructParametricType(com.nafru.email.model.ListResponse.class, item);
    }

    static String write(Object value) {
        try {
            return MAPPER.writeValueAsString(value);
        } catch (JsonProcessingException e) {
            throw new IllegalArgumentException("Gövde JSON'a çevrilemedi: " + e.getOriginalMessage(), e);
        }
    }

    static <T> T read(String text, JavaType type) {
        try {
            return MAPPER.readValue(text, type);
        } catch (JsonProcessingException e) {
            throw NafruException.network("Yanıt ayrıştırılamadı: " + e.getOriginalMessage());
        }
    }
}
