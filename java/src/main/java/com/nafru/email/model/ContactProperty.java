package com.nafru.email.model;

/** {@code fallbackValue}: metin, sayı ya da {@code null}; {@code object} yalnız {@code get} yanıtında dolu. */
public record ContactProperty(String id, String object, String key, String type, Object fallbackValue, String createdAt)
        implements Identified {}
