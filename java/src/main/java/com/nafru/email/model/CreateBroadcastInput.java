package com.nafru.email.model;

public final class CreateBroadcastInput extends Params<CreateBroadcastInput> {
    public CreateBroadcastInput(String segmentId, String from) {
        set("segment_id", segmentId);
        set("from", from);
    }

    /** Boşsa konu satırı. */
    public CreateBroadcastInput name(String value) { return set("name", value); }
    public CreateBroadcastInput topicId(String value) { return set("topic_id", value); }
    public CreateBroadcastInput subject(String value) { return set("subject", value); }
    public CreateBroadcastInput replyTo(String... value) { return addresses("reply_to", value); }
    public CreateBroadcastInput html(String value) { return set("html", value); }
    public CreateBroadcastInput text(String value) { return set("text", value); }
    /** Şablon kimliği ya da takma adı; {@code html}/{@code text} ile birlikte verilmez. */
    public CreateBroadcastInput templateId(String value) { return set("template_id", value); }
    public CreateBroadcastInput previewText(String value) { return set("preview_text", value); }
    /** {@code true}: aynı istekte gönderir. {@code scheduledAt} yalnız bununla anlamlıdır. */
    public CreateBroadcastInput send(boolean value) { return set("send", value); }
    public CreateBroadcastInput scheduledAt(String value) { return set("scheduled_at", value); }
    public CreateBroadcastInput openTracking(boolean value) { return set("open_tracking", value); }
    public CreateBroadcastInput clickTracking(boolean value) { return set("click_tracking", value); }
    /** {@code {{{data.*}}}} değişkenlerinin değeri (JSON nesne, ≤ 256 KB); {@code null} temizler. */
    public CreateBroadcastInput data(java.util.Map<String, ?> value) { return set("data", value); }
    public CreateBroadcastInput dataSource(BroadcastDataSourceInput value) { return set("data_source", value); }
    /** Verilirse kayıt tekrarlayan bir şablondur: {@code send} onu etkinleştirir; {@code null} temizler. */
    public CreateBroadcastInput recurrence(BroadcastRecurrence value) { return set("recurrence", value); }
}
