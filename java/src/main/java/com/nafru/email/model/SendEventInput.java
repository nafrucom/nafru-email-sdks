package com.nafru.email.model;

import java.util.Map;

public final class SendEventInput extends Params<SendEventInput> {
    /** {@code ^[a-z0-9_.:-]{1,64}$}; {@code email.}, {@code contact.}, {@code segment.}, {@code topic.}, {@code automation.} ön ekleri ayrılmıştır. */
    public SendEventInput(String name) { set("name", name); }

    /** Kişi yoksa oluşturulur. */
    public SendEventInput contactEmail(String email) { return set("contact", Map.of("email", email)); }
    /** Kimlikle verilen kişi yoksa 404. */
    public SendEventInput contactId(String id) { return set("contact", Map.of("id", id)); }
    /** Değerler metin, sayı, mantıksal ya da {@code null}. */
    public SendEventInput properties(Map<String, ?> value) { return set("properties", value); }
    /** ISO 8601; verilmezse alma anı. */
    public SendEventInput occurredAt(String value) { return set("occurred_at", value); }
    /** Yalnız kişi bu istekle oluşturuluyorsa: kişiyi abonelikten çıkmış açar. */
    public SendEventInput unsubscribed(boolean value) { return set("unsubscribed", value); }
}
