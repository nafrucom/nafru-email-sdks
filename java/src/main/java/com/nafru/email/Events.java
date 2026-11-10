package com.nafru.email;

import com.nafru.email.model.BatchResponse;
import com.nafru.email.model.EventItem;
import com.nafru.email.model.IdResponse;
import com.nafru.email.model.ListEventsQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.SendEventInput;
import java.util.List;

/** Otomasyonları tetikleyen özel olay API'si. */
public final class Events {
    private final Http.Caller http;

    Events(Http.Caller http) { this.http = http; }

    public IdResponse send(SendEventInput input) { return send(input, null); }

    /** {@code idempotencyKey}: aynı anahtarla yinelenen istek olayı bir kez işler. */
    public IdResponse send(SendEventInput input, String idempotencyKey) {
        return http.call(Http.Request.post("/events", input, idempotencyKey), IdResponse.class);
    }

    public BatchResponse batch(List<SendEventInput> input) { return batch(input, null); }

    /** En çok 100 olay; biri geçersizse tüm istek 422. */
    public BatchResponse batch(List<SendEventInput> input, String idempotencyKey) {
        return http.call(Http.Request.post("/events/batch", input, idempotencyKey), BatchResponse.class);
    }

    public ListResponse<EventItem> list() { return list(new ListEventsQuery()); }

    public ListResponse<EventItem> list(ListEventsQuery query) {
        return http.call(Http.Request.get("/events", query.toMap()), Json.listOf(EventItem.class));
    }
}
