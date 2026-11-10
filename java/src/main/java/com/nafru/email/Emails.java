package com.nafru.email;

import com.nafru.email.model.BatchEmailItem;
import com.nafru.email.model.BatchResponse;
import com.nafru.email.model.Email;
import com.nafru.email.model.IdResponse;
import com.nafru.email.model.ListEmailsQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.SendEmailInput;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;

public final class Emails {
    private final Http.Caller http;
    private final String devOutbox;

    Emails(Http.Caller http, String devOutbox) {
        this.http = http;
        this.devOutbox = devOutbox;
    }

    /** {@code POST /emails}. {@code scheduledAt} verilirse zamanlanır. */
    public IdResponse send(SendEmailInput input) {
        return send(input, null);
    }

    /** {@code idempotencyKey} ({@code Idempotency-Key}) ile yineleme güvenlidir: aynı anahtar aynı e-postayı döndürür. */
    public IdResponse send(SendEmailInput input, String idempotencyKey) {
        if (devOutbox != null) return DevOutbox.write(devOutbox, input.toMap());
        return http.call(Http.Request.post("/emails", input, idempotencyKey), IdResponse.class);
    }

    /** {@code POST /emails/batch}: en çok 100 e-posta; ek ve şablon desteklenmez. */
    public BatchResponse batch(List<BatchEmailItem> input) {
        return batch(input, null);
    }

    public BatchResponse batch(List<BatchEmailItem> input, String idempotencyKey) {
        if (devOutbox == null) {
            return http.call(Http.Request.post("/emails/batch", input, idempotencyKey), BatchResponse.class);
        }
        List<IdResponse> data = new ArrayList<>();
        for (BatchEmailItem item : input) data.add(DevOutbox.write(devOutbox, item.toMap()));
        return new BatchResponse(data);
    }

    public Email get(String id) {
        return http.call(Http.Request.get("/emails/" + Http.seg(id)), Email.class);
    }

    public ListResponse<Email> list() {
        return list(new ListEmailsQuery());
    }

    public ListResponse<Email> list(ListEmailsQuery query) {
        return http.call(Http.Request.get("/emails", query.toMap()), Json.listOf(Email.class));
    }

    /** Zamanlanmış e-postanın gönderim anını değiştirir. */
    public Ref update(String id, String scheduledAt) {
        return http.call(Http.Request.patch("/emails/" + Http.seg(id), Map.of("scheduled_at", scheduledAt)), Ref.class);
    }

    /** Zamanlanmış e-postayı iptal eder. */
    public Ref cancel(String id) {
        return http.call(Http.Request.post("/emails/" + Http.seg(id) + "/cancel", null), Ref.class);
    }
}
