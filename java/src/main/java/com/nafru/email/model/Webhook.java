package com.nafru.email.model;

import com.nafru.email.Redact;

import java.util.List;

/** Webhook; {@code signingSecret} yalnız {@code create} ve {@code get} yanıtında, {@code verifyWebhook} bununla doğrular. */
public record Webhook(
        String id,
        String object,
        String endpoint,
        String createdAt,
        String status,
        List<String> events,
        String signingSecret) implements Identified {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "Webhook[id=" + id + ", object=" + object + ", endpoint=" + endpoint + ", createdAt=" + createdAt + ", status=" + status
                + ", events=" + events + ", signingSecret=" + Redact.mask(signingSecret) + "]";
    }
}
