package com.nafru.email;

import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.Contact;
import com.nafru.email.model.ListContactsQuery;
import java.util.ArrayList;
import java.util.List;
import org.junit.jupiter.api.Test;

class PaginationTest {
    @Test
    void walksPagesWithAfterCursor() {
        MockTransport mock = MockTransport.sequence(
                MockTransport.ok("{\"object\":\"list\",\"data\":[{\"id\":\"a\"},{\"id\":\"b\"}],\"has_more\":true}"),
                MockTransport.ok("{\"object\":\"list\",\"data\":[{\"id\":\"c\"}],\"has_more\":false}"));
        NafruEmail nafru = mock.client(0);
        ListContactsQuery query = new ListContactsQuery().limit(2);
        List<String> ids = new ArrayList<>();
        for (Contact contact : Pagination.paginate(nafru.contacts()::list, query)) ids.add(contact.id());
        assertEquals(List.of("a", "b", "c"), ids);
        assertEquals(List.of("http://api.localhost/contacts?limit=2", "http://api.localhost/contacts?limit=2&after=b"),
                mock.calls.stream().map(Transport.Request::url).toList());
        assertNull(query.toMap().get("after"));
    }

    @Test
    void throwsOnError() {
        MockTransport mock = MockTransport.sequence(
                MockTransport.json(401, "{\"statusCode\":401,\"name\":\"unauthorized\",\"message\":\"anahtar yok\"}"));
        NafruEmail nafru = mock.client(0);
        NafruException error = assertThrows(NafruException.class,
                () -> Pagination.paginate(nafru.contacts()::list, new ListContactsQuery()).iterator().hasNext());
        assertEquals("anahtar yok", error.getMessage());
        assertEquals(401, error.getStatusCode());
    }
}
