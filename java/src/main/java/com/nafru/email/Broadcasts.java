package com.nafru.email;

import com.nafru.email.model.Broadcast;
import com.nafru.email.model.CreateBroadcastInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.SendBroadcastInput;
import com.nafru.email.model.UpdateBroadcastInput;

public final class Broadcasts {
    private final Http.Caller http;

    Broadcasts(Http.Caller http) { this.http = http; }

    private static String path(String id) { return "/broadcasts/" + Http.seg(id); }

    /** Taslak oluşturur; {@code send(true)} ile aynı istekte gönderir. */
    public Ref create(CreateBroadcastInput input) {
        return http.call(Http.Request.post("/broadcasts", input), Ref.class);
    }

    public Broadcast get(String id) {
        return http.call(Http.Request.get(path(id)), Broadcast.class);
    }

    public ListResponse<Broadcast> list() { return list(new ListQuery()); }

    public ListResponse<Broadcast> list(ListQuery query) {
        return http.call(Http.Request.get("/broadcasts", query.toMap()), Json.listOf(Broadcast.class));
    }

    /** Yalnız taslakta (aksi 409). */
    public Ref update(String id, UpdateBroadcastInput input) {
        return http.call(Http.Request.patch(path(id), input), Ref.class);
    }

    /** Yalnız taslakta (aksi 409). */
    public Deleted remove(String id) {
        return http.call(Http.Request.delete(path(id)), Deleted.class);
    }

    public Ref send(String id) { return send(id, new SendBroadcastInput()); }

    public Ref send(String id, SendBroadcastInput input) {
        return http.call(Http.Request.post(path(id) + "/send", input), Ref.class);
    }

    public Ref cancel(String id) {
        return http.call(Http.Request.post(path(id) + "/cancel", null), Ref.class);
    }
}
