package com.nafru.email.model;

/** {@code permission}: {@code full_access} ya da {@code sending_access}. */
public record ApiKey(
        String id,
        String name,
        String createdAt,
        String lastUsedAt,
        String permission,
        String domainId,
        String tokenPrefix) implements Identified {}
