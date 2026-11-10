package com.nafru.email.model;

import java.util.List;

/** Alan adı; {@code object} ve {@code records} yalnız ayrıntı yanıtında ({@code create}, {@code get}) dolu. */
public record Domain(
        String id,
        String object,
        String name,
        String status,
        String createdAt,
        String region,
        Capabilities capabilities,
        Boolean openTracking,
        Boolean clickTracking,
        String tls,
        String trackingSubdomain,
        List<DomainRecord> records) implements Identified {
    public record Capabilities(String sending, String receiving) {}
}
