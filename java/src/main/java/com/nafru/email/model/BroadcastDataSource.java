package com.nafru.email.model;

import com.nafru.email.Redact;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;

/** Yanıttaki veri kaynağı: url'de başlık değeri maskelenir ({@code hasHeaderValue}). Bilinmeyen tür {@link Unknown} olarak okunur. */
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, property = "type", defaultImpl = BroadcastDataSource.Unknown.class)
@JsonSubTypes({
    @JsonSubTypes.Type(value = BroadcastDataSource.Manual.class, name = "manual"),
    @JsonSubTypes.Type(value = BroadcastDataSource.Url.class, name = "url"),
    @JsonSubTypes.Type(value = BroadcastDataSource.Webhook.class, name = "webhook")
})
public sealed interface BroadcastDataSource {
    record Manual() implements BroadcastDataSource {}

    record Url(String url, String headerName, boolean hasHeaderValue) implements BroadcastDataSource {}

    /** {@code triggerUrl} ve {@code secret} yalnız tam yetkili anahtarla görünür. */
    record Webhook(String triggerUrl, String secret) implements BroadcastDataSource {
        @Override
        public String toString() {
            return "Webhook[triggerUrl=" + triggerUrl + ", secret=" + Redact.mask(secret) + "]";
        }
    }

    /** SDK'nın henüz tanımadığı tür. */
    record Unknown() implements BroadcastDataSource {}
}
