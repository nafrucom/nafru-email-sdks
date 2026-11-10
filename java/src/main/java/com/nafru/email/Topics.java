package com.nafru.email;

import com.nafru.email.model.CreateTopicInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.Topic;
import com.nafru.email.model.UpdateTopicInput;

public final class Topics {
    private final Http.Caller http;

    Topics(Http.Caller http) { this.http = http; }

    public Ref create(CreateTopicInput input) {
        return http.call(Http.Request.post("/topics", input), Ref.class);
    }

    public Topic get(String id) {
        return http.call(Http.Request.get("/topics/" + Http.seg(id)), Topic.class);
    }

    public ListResponse<Topic> list() { return list(new ListQuery()); }

    public ListResponse<Topic> list(ListQuery query) {
        return http.call(Http.Request.get("/topics", query.toMap()), Json.listOf(Topic.class));
    }

    public Ref update(String id, UpdateTopicInput input) {
        return http.call(Http.Request.patch("/topics/" + Http.seg(id), input), Ref.class);
    }

    public Deleted remove(String id) {
        return http.call(Http.Request.delete("/topics/" + Http.seg(id)), Deleted.class);
    }
}
