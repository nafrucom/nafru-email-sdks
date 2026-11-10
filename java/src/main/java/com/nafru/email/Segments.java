package com.nafru.email;

import com.nafru.email.model.Contact;
import com.nafru.email.model.CreateSegmentInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Segment;
import com.nafru.email.model.SegmentRef;

public final class Segments {
    private final Http.Caller http;

    Segments(Http.Caller http) { this.http = http; }

    public SegmentRef create(CreateSegmentInput input) {
        return http.call(Http.Request.post("/segments", input), SegmentRef.class);
    }

    public Segment get(String id) {
        return http.call(Http.Request.get("/segments/" + Http.seg(id)), Segment.class);
    }

    public ListResponse<Segment> list() { return list(new ListQuery()); }

    public ListResponse<Segment> list(ListQuery query) {
        return http.call(Http.Request.get("/segments", query.toMap()), Json.listOf(Segment.class));
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/segments/" + Http.seg(id)), Deleted.class);
    }

    public ListResponse<Contact> contacts(String id) { return contacts(id, new ListQuery()); }

    /** Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız {@code limit} ve {@code after}. */
    public ListResponse<Contact> contacts(String id, ListQuery query) {
        return http.call(Http.Request.get("/segments/" + Http.seg(id) + "/contacts", query.toMap()), Json.listOf(Contact.class));
    }
}
