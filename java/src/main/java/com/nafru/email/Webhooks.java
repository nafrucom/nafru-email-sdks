package com.nafru.email;

import com.nafru.email.model.CreateWebhookInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.UpdateWebhookInput;
import com.nafru.email.model.Webhook;

public final class Webhooks {
    private final Http.Caller http;

    Webhooks(Http.Caller http) { this.http = http; }

    /** Yanıttaki {@code signingSecret} ile {@link WebhookVerifier} kullanılır. */
    public Webhook create(CreateWebhookInput input) {
        return http.call(Http.Request.post("/webhooks", input), Webhook.class);
    }

    public Webhook get(String id) {
        return http.call(Http.Request.get("/webhooks/" + Http.seg(id)), Webhook.class);
    }

    public ListResponse<Webhook> list() { return list(new ListQuery()); }

    public ListResponse<Webhook> list(ListQuery query) {
        return http.call(Http.Request.get("/webhooks", query.toMap()), Json.listOf(Webhook.class));
    }

    public Ref update(String id, UpdateWebhookInput input) {
        return http.call(Http.Request.patch("/webhooks/" + Http.seg(id), input), Ref.class);
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/webhooks/" + Http.seg(id)), Deleted.class);
    }
}
