package com.nafru.email;

import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.BatchEmailItem;
import com.nafru.email.model.Contact;
import com.nafru.email.model.CreateContactPropertyInput;
import com.nafru.email.model.CreateDomainInput;
import com.nafru.email.model.CreateTopicInput;
import com.nafru.email.model.ListEmailsQuery;
import com.nafru.email.model.ListQuery;
import com.nafru.email.model.PutTemplateTranslationInput;
import com.nafru.email.model.SendEventInput;
import com.nafru.email.model.TopicSubscription;
import java.util.List;
import java.util.Map;
import java.util.function.Consumer;
import org.junit.jupiter.api.Test;

class ResourcesTest {
    private static String request(Consumer<NafruEmail> run) {
        MockTransport mock = MockTransport.sequence(MockTransport.ok("{}"));
        run.accept(mock.client(0));
        Transport.Request call = mock.calls.get(0);
        return call.method() + " " + call.url().replace("http://api.localhost", "") + (call.body() == null ? "" : " " + call.body());
    }

    @Test
    void mapsMethodsPathsAndBodies() {
        assertEquals("POST /emails/batch [{\"from\":\"a@x.test\",\"to\":\"b@x.test\",\"subject\":\"s\",\"text\":\"t\"}]",
                request(n -> n.emails().batch(List.of(new BatchEmailItem().from("a@x.test").to("b@x.test").subject("s").text("t")))));
        assertEquals("GET /emails/e%201", request(n -> n.emails().get("e 1")));
        assertEquals("GET /emails?limit=2&status=sent", request(n -> n.emails().list(new ListEmailsQuery().limit(2).status("sent"))));
        assertEquals("PATCH /emails/e1 {\"scheduled_at\":\"in 1 hour\"}", request(n -> n.emails().update("e1", "in 1 hour")));
        assertEquals("POST /emails/e1/cancel", request(n -> n.emails().cancel("e1")));
        assertEquals("POST /domains {\"name\":\"x.test\"}", request(n -> n.domains().create(new CreateDomainInput("x.test"))));
        assertEquals("POST /domains/d1/verify", request(n -> n.domains().verify("d1")));
        assertEquals("DELETE /domains/d1", request(n -> n.domains().remove("d1")));
        assertEquals("GET /contacts/a%2Bb%40x.test", request(n -> n.contacts().get("a+b@x.test")));
        assertEquals("POST /contacts/c1/segments/s1", request(n -> n.contacts().segments().add("c1", "s1")));
        assertEquals("DELETE /contacts/c1/segments/s1", request(n -> n.contacts().segments().remove("c1", "s1")));
        assertEquals("GET /contacts/c1/topics", request(n -> n.contacts().topics().list("c1")));
        assertEquals("PATCH /contacts/c1/topics [{\"id\":\"t1\",\"subscription\":\"opt_in\"}]",
                request(n -> n.contacts().topics().update("c1", List.of(new TopicSubscription("t1", "opt_in")))));
        assertEquals("POST /contact-properties {\"key\":\"plan\",\"type\":\"string\"}",
                request(n -> n.contactProperties().create(new CreateContactPropertyInput("plan", "string"))));
        assertEquals("GET /segments/s1/contacts?limit=3", request(n -> n.segments().contacts("s1", new ListQuery().limit(3))));
        assertEquals("POST /topics {\"name\":\"Haber\",\"default_subscription\":\"opt_out\"}",
                request(n -> n.topics().create(new CreateTopicInput("Haber", "opt_out"))));
        assertEquals("POST /broadcasts/b1/send {}", request(n -> n.broadcasts().send("b1")));
        assertEquals("PUT /templates/welcome/translations/pt-BR {\"html\":\"<p>x</p>\"}",
                request(n -> n.templates().putTranslation("welcome", "pt-BR", new PutTemplateTranslationInput("<p>x</p>"))));
        assertEquals("POST /events {\"name\":\"plan_upgraded\",\"contact\":{\"email\":\"a@x.test\"},\"properties\":{\"seats\":3}}",
                request(n -> n.events().send(new SendEventInput("plan_upgraded").contactEmail("a@x.test").properties(Map.of("seats", 3)))));
        assertEquals("DELETE /api-keys/k1", request(n -> n.apiKeys().remove("k1")));
    }

    @Test
    void decodesSnakeCaseResponses() {
        MockTransport mock = MockTransport.sequence(MockTransport.ok(
                "{\"object\":\"contact\",\"id\":\"c1\",\"email\":\"a@x.test\",\"first_name\":\"Ali\",\"unsubscribed\":false,"
                        + "\"properties\":{\"plan\":{\"type\":\"string\",\"value\":\"pro\"}},\"yeni_alan\":1}"));
        Contact contact = mock.client(0).contacts().get("c1");
        assertEquals("Ali", contact.firstName());
        assertEquals("pro", contact.properties().get("plan").value());
    }
}
