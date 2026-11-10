package com.nafru.email;

import com.nafru.email.model.ContactProperty;
import com.nafru.email.model.CreateContactPropertyInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.UpdateContactPropertyInput;

public final class ContactProperties {
    private final Http.Caller http;

    ContactProperties(Http.Caller http) { this.http = http; }

    public Ref create(CreateContactPropertyInput input) {
        return http.call(Http.Request.post("/contact-properties", input), Ref.class);
    }

    public ContactProperty get(String id) {
        return http.call(Http.Request.get("/contact-properties/" + Http.seg(id)), ContactProperty.class);
    }

    public ListResponse<ContactProperty> list() { return list(new ListQuery()); }

    public ListResponse<ContactProperty> list(ListQuery query) {
        return http.call(Http.Request.get("/contact-properties", query.toMap()), Json.listOf(ContactProperty.class));
    }

    public Ref update(String id, UpdateContactPropertyInput input) {
        return http.call(Http.Request.patch("/contact-properties/" + Http.seg(id), input), Ref.class);
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/contact-properties/" + Http.seg(id)), Deleted.class);
    }
}
