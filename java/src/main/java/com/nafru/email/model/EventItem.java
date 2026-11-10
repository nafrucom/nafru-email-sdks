package com.nafru.email.model;

import java.util.Map;

/** {@code source}: {@code api} ya da {@code system}. */
public record EventItem(
        String id,
        String name,
        String contactId,
        String email,
        Map<String, Object> properties,
        String source,
        String occurredAt,
        String createdAt) implements Identified {}
