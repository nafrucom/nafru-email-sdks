package com.nafru.email;

import com.nafru.email.model.CreateDomainInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.Domain;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.UpdateDomainInput;

public final class Domains {
    private final Http.Caller http;

    Domains(Http.Caller http) { this.http = http; }

    public Domain create(CreateDomainInput input) {
        return http.call(Http.Request.post("/domains", input), Domain.class);
    }

    public Domain get(String id) {
        return http.call(Http.Request.get("/domains/" + Http.seg(id)), Domain.class);
    }

    public ListResponse<Domain> list() { return list(new ListQuery()); }

    public ListResponse<Domain> list(ListQuery query) {
        return http.call(Http.Request.get("/domains", query.toMap()), Json.listOf(Domain.class));
    }

    public Ref update(String id, UpdateDomainInput input) {
        return http.call(Http.Request.patch("/domains/" + Http.seg(id), input), Ref.class);
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/domains/" + Http.seg(id)), Deleted.class);
    }

    /** DNS kayıtlarını denetletir; sonuç {@code get} ile okunur. */
    public Ref verify(String id) {
        return http.call(Http.Request.post("/domains/" + Http.seg(id) + "/verify", null), Ref.class);
    }
}
