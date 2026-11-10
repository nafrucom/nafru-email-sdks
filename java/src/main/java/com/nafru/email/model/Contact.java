package com.nafru.email.model;

import java.util.Map;

/** Kişi; {@code object} ve {@code properties} yalnız {@code get} yanıtında dolu. */
public record Contact(
        String id,
        String object,
        String email,
        String firstName,
        String lastName,
        boolean unsubscribed,
        String locale,
        String createdAt,
        Map<String, PropertyValue> properties) implements Identified {
    /** {@code type}: {@code string} ya da {@code number}. */
    public record PropertyValue(String type, Object value) {}
}
