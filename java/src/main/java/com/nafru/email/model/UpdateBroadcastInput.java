package com.nafru.email.model;

import java.util.List;

public final class UpdateBroadcastInput extends Params<UpdateBroadcastInput> {
    public UpdateBroadcastInput name(String value) { return set("name", value); }
    public UpdateBroadcastInput segmentId(String value) { return set("segment_id", value); }
    public UpdateBroadcastInput topicId(String value) { return set("topic_id", value); }
    public UpdateBroadcastInput from(String value) { return set("from", value); }
    public UpdateBroadcastInput subject(String value) { return set("subject", value); }
    public UpdateBroadcastInput replyTo(String... value) { return set("reply_to", value == null ? null : List.of(value)); }
    public UpdateBroadcastInput html(String value) { return set("html", value); }
    public UpdateBroadcastInput text(String value) { return set("text", value); }
    public UpdateBroadcastInput previewText(String value) { return set("preview_text", value); }
    public UpdateBroadcastInput openTracking(boolean value) { return set("open_tracking", value); }
    public UpdateBroadcastInput clickTracking(boolean value) { return set("click_tracking", value); }
    /** {@code {{{data.*}}}} değişkenlerinin değeri (JSON nesne, ≤ 256 KB); {@code null} temizler. */
    public UpdateBroadcastInput data(java.util.Map<String, ?> value) { return set("data", value); }
    public UpdateBroadcastInput dataSource(BroadcastDataSourceInput value) { return set("data_source", value); }
    /** Verilirse kayıt tekrarlayan bir şablondur: {@code send} onu etkinleştirir; {@code null} temizler. */
    public UpdateBroadcastInput recurrence(BroadcastRecurrence value) { return set("recurrence", value); }
}
