package com.nafru.email.model;

public final class SendBroadcastInput extends Params<SendBroadcastInput> {
    public SendBroadcastInput scheduledAt(String value) { return set("scheduled_at", value); }
    /** Bu gönderimin {@code {{{data.*}}}} bağlamı (taslaktakinin yerine). */
    public SendBroadcastInput data(java.util.Map<String, ?> value) { return set("data", value); }
}
