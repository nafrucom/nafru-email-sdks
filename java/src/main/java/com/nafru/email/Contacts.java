package com.nafru.email;

import com.nafru.email.model.Contact;
import com.nafru.email.model.ContactTopic;
import com.nafru.email.model.CreateContactInput;
import com.nafru.email.model.Deleted;
import com.nafru.email.model.DeletedContact;
import com.nafru.email.model.IdResponse;
import com.nafru.email.model.ListContactsQuery;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.Ref;
import com.nafru.email.model.Segment;
import com.nafru.email.model.TopicSubscription;
import com.nafru.email.model.UpdateContactInput;
import java.util.List;

/** Kişi uçlarında {@code id} yerine e-posta adresi de verilebilir. */
public final class Contacts {
    private final Http.Caller http;
    private final ContactSegments segments;
    private final ContactTopics topics;

    Contacts(Http.Caller http) {
        this.http = http;
        this.segments = new ContactSegments(http);
        this.topics = new ContactTopics(http);
    }

    private static String path(String idOrEmail) { return "/contacts/" + Http.seg(idOrEmail); }

    public Ref create(CreateContactInput input) {
        return http.call(Http.Request.post("/contacts", input), Ref.class);
    }

    public Contact get(String idOrEmail) {
        return http.call(Http.Request.get(path(idOrEmail)), Contact.class);
    }

    public ListResponse<Contact> list() { return list(new ListContactsQuery()); }

    public ListResponse<Contact> list(ListContactsQuery query) {
        return http.call(Http.Request.get("/contacts", query.toMap()), Json.listOf(Contact.class));
    }

    public Ref update(String idOrEmail, UpdateContactInput input) {
        return http.call(Http.Request.patch(path(idOrEmail), input), Ref.class);
    }

    public DeletedContact remove(String idOrEmail) {
        return http.call(Http.Request.delete(path(idOrEmail)), DeletedContact.class);
    }

    public ContactSegments segments() { return segments; }

    public ContactTopics topics() { return topics; }

    public static final class ContactSegments {
        private final Http.Caller http;

        ContactSegments(Http.Caller http) { this.http = http; }

        public ListResponse<Segment> list(String idOrEmail) { return list(idOrEmail, new ListQuery()); }

        public ListResponse<Segment> list(String idOrEmail, ListQuery query) {
            return http.call(Http.Request.get(path(idOrEmail) + "/segments", query.toMap()), Json.listOf(Segment.class));
        }

        /** Kişiyi statik segmente ekler (dinamik segmentte 422). */
        public IdResponse add(String idOrEmail, String segmentId) {
            return http.call(Http.Request.post(path(idOrEmail) + "/segments/" + Http.seg(segmentId), null), IdResponse.class);
        }

        public Deleted remove(String idOrEmail, String segmentId) {
            return http.call(Http.Request.delete(path(idOrEmail) + "/segments/" + Http.seg(segmentId)), Deleted.class);
        }
    }

    public static final class ContactTopics {
        private final Http.Caller http;

        ContactTopics(Http.Caller http) { this.http = http; }

        public ListResponse<ContactTopic> list(String idOrEmail) { return list(idOrEmail, new ListQuery()); }

        public ListResponse<ContactTopic> list(String idOrEmail, ListQuery query) {
            return http.call(Http.Request.get(path(idOrEmail) + "/topics", query.toMap()), Json.listOf(ContactTopic.class));
        }

        public Ref update(String idOrEmail, List<TopicSubscription> topics) {
            // Sunucu gövdede çıplak dizi bekler.
            return http.call(Http.Request.patch(path(idOrEmail) + "/topics", topics), Ref.class);
        }
    }
}
