package com.nafru.email;

import com.nafru.email.model.ApiKey;
import com.nafru.email.model.CreateApiKeyInput;
import com.nafru.email.model.CreatedApiKey;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;

public final class ApiKeys {
    private final Http.Caller http;

    ApiKeys(Http.Caller http) { this.http = http; }

    public CreatedApiKey create(CreateApiKeyInput input) {
        return http.call(Http.Request.post("/api-keys", input), CreatedApiKey.class);
    }

    public ListResponse<ApiKey> list() { return list(new ListQuery()); }

    public ListResponse<ApiKey> list(ListQuery query) {
        return http.call(Http.Request.get("/api-keys", query.toMap()), Json.listOf(ApiKey.class));
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/api-keys/" + Http.seg(id)), Deleted.class);
    }
}
