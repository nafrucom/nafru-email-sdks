package com.nafru.email.model;

/** {@code object} yalnız {@code get} yanıtında dolu. */
public record Topic(
        String id,
        String object,
        String name,
        String description,
        String defaultSubscription,
        String visibility,
        boolean doubleOptIn,
        String createdAt) implements Identified {}
