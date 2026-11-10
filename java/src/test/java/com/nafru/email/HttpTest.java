package com.nafru.email;

import static com.nafru.email.MockTransport.json;
import static com.nafru.email.MockTransport.ok;
import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.ListContactsQuery;
import com.nafru.email.model.SendEmailInput;
import com.nafru.email.model.UpdateContactInput;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.PrintStream;
import java.net.http.HttpTimeoutException;
import java.nio.charset.StandardCharsets;
import java.util.Map;
import org.junit.jupiter.api.Test;

class HttpTest {
    private static final SendEmailInput EMAIL = new SendEmailInput().from("a@x.test").to("b@x.test").subject("s").text("t");
    private static final String LIMITED = "{\"statusCode\":429,\"name\":\"rate_limit_exceeded\",\"message\":\"yavaş\"}";

    @Test
    void sendsAuthUserAgentJsonAndIdempotencyKey() {
        MockTransport mock = MockTransport.sequence(ok("{\"id\":\"e1\"}"));
        assertEquals("e1", mock.client(0).emails().send(EMAIL, "k-1").id());
        Transport.Request call = mock.calls.get(0);
        assertEquals("http://api.localhost/emails", call.url());
        assertEquals("POST", call.method());
        assertEquals("Bearer key_test", call.headers().get("authorization"));
        assertEquals("application/json", call.headers().get("content-type"));
        assertEquals("k-1", call.headers().get("idempotency-key"));
        assertEquals("nafru-email-java/" + NafruEmail.SDK_VERSION, call.headers().get("user-agent"));
        assertEquals("{\"from\":\"a@x.test\",\"to\":\"b@x.test\",\"subject\":\"s\",\"text\":\"t\"}", call.body());
    }

    @Test
    void explicitNullIsSentAndUnsetFieldsAreNot() {
        MockTransport mock = MockTransport.sequence(ok("{\"object\":\"contact\",\"id\":\"c1\"}"));
        mock.client(0).contacts().update("c1", new UpdateContactInput().firstName(null).unsubscribed(true));
        assertEquals("{\"first_name\":null,\"unsubscribed\":true}", mock.calls.get(0).body());
    }

    @Test
    void queryCarriesOnlyFilledValues() {
        MockTransport mock = MockTransport.sequence(ok("{\"object\":\"list\",\"data\":[],\"has_more\":false}"));
        mock.client(0).contacts().list(new ListContactsQuery().limit(5).after(null).search("ali ç"));
        assertEquals("http://api.localhost/contacts?limit=5&search=ali+%C3%A7", mock.calls.get(0).url());
    }

    @Test
    void parsesErrorBody() {
        String body = "{\"statusCode\":422,\"name\":\"validation_error\",\"message\":\"Geçersiz\","
                + "\"errors\":[{\"field\":\"to\",\"message\":\"zorunlu\",\"i18nTranslationKey\":\"k\"}]}";
        MockTransport mock = MockTransport.sequence(json(422, body));
        NafruException error = assertThrows(NafruException.class, () -> mock.client(0).emails().send(EMAIL));
        assertEquals(422, error.getStatusCode());
        assertEquals("validation_error", error.getName());
        assertEquals("Geçersiz", error.getMessage());
        assertEquals(new FieldError("to", "zorunlu", "k"), error.getErrors().get(0));
        assertNull(error.getRetryAfter());
    }

    @Test
    void buildsErrorFromStatusWhenBodyIsNotStandard() {
        MockTransport mock = MockTransport.sequence(json(502, "<html>bad gateway</html>"));
        NafruException error = assertThrows(NafruException.class, () -> mock.client(0).emails().get("e1"));
        assertEquals(502, error.getStatusCode());
        assertEquals("application_error", error.getName());
        MockTransport notFound = MockTransport.sequence(json(404, ""));
        assertEquals("not_found", assertThrows(NafruException.class, () -> notFound.client(0).emails().get("e1")).getName());
    }

    @Test
    void networkErrorHasNullStatus() {
        MockTransport mock = new MockTransport(request -> { throw new IOException("fetch failed"); });
        NafruException error = assertThrows(NafruException.class, () -> mock.client(0).emails().send(EMAIL));
        assertNull(error.getStatusCode());
        assertEquals("application_error", error.getName());
        assertEquals("fetch failed", error.getMessage());
    }

    @Test
    void timeoutGivesTimeoutError() {
        MockTransport mock = new MockTransport(request -> { throw new HttpTimeoutException("timed out"); });
        NafruException error = assertThrows(NafruException.class, () -> mock.client(0).emails().get("e1"));
        assertNull(error.getStatusCode());
        assertEquals("timeout_error", error.getName());
    }

    @Test
    void retries429WithRetryAfterEvenForPost() {
        MockTransport mock = MockTransport.sequence(json(429, LIMITED, Map.of("retry-after", "0")), ok("{\"id\":\"e1\"}"));
        assertEquals("e1", mock.client(2).emails().send(EMAIL).id());
        assertEquals(2, mock.calls.size());
    }

    @Test
    void exhausted429ReturnsRetryAfter() {
        MockTransport mock = MockTransport.sequence(json(429, LIMITED, Map.of("retry-after", "0")));
        NafruException error = assertThrows(NafruException.class, () -> mock.client(1).emails().get("e1"));
        assertEquals("rate_limit_exceeded", error.getName());
        assertEquals(0.0, error.getRetryAfter());
        assertEquals(2, mock.calls.size());
    }

    @Test
    void retriesGet5xxButNotPostWithoutKey() {
        String down = "{\"statusCode\":500,\"name\":\"application_error\",\"message\":\"x\"}";
        MockTransport get = MockTransport.sequence(json(500, down), ok("{\"id\":\"e1\"}"));
        assertEquals("e1", get.client(1).emails().get("e1").id());
        assertEquals(2, get.calls.size());

        MockTransport post = MockTransport.sequence(json(500, down), ok("{\"id\":\"e1\"}"));
        assertEquals(500, assertThrows(NafruException.class, () -> post.client(1).emails().send(EMAIL)).getStatusCode());
        assertEquals(1, post.calls.size());
    }

    @Test
    void retriesPost5xxWithIdempotencyKey() {
        MockTransport mock = MockTransport.sequence(json(503, "{\"message\":\"x\"}"), ok("{\"id\":\"e1\"}"));
        assertEquals("e1", mock.client(1).emails().send(EMAIL, "k-1").id());
        assertEquals(2, mock.calls.size());
        assertEquals("k-1", mock.calls.get(1).headers().get("idempotency-key"));
    }

    @Test
    void apiKeyRequiredAndBaseUrlDefaults() {
        var original = NafruEmail.env;
        NafruEmail.env = name -> null;
        try {
            assertThrows(IllegalArgumentException.class, () -> NafruEmail.builder().apiKey("").build());
            assertThrows(IllegalArgumentException.class, NafruEmail::new);
        } finally {
            NafruEmail.env = original;
        }
        for (String baseUrl : new String[] {null, ""}) {
            MockTransport mock = MockTransport.sequence(ok("{\"id\":\"e1\"}"));
            NafruEmail.builder().apiKey("k").baseUrl(baseUrl).transport(mock).devOutbox(false).build().emails().get("e1");
            assertEquals(NafruEmail.DEFAULT_BASE_URL + "/emails/e1", mock.calls.get(0).url());
        }
    }

    @Test
    void apiKeyFallsBackToEnvironment() {
        var original = NafruEmail.env;
        NafruEmail.env = name -> name.equals("NAFRU_API_KEY") ? "nafru_env" : null;
        try {
            MockTransport mock = MockTransport.sequence(ok("{\"id\":\"e1\"}"));
            NafruEmail.builder().transport(mock).build().emails().get("e1");
            assertEquals("Bearer nafru_env", mock.calls.get(0).headers().get("authorization"));
            assertDoesNotThrow(() -> new NafruEmail());
            assertDoesNotThrow(() -> new NafruEmail(""));
        } finally {
            NafruEmail.env = original;
        }
    }

    @Test
    void positionalApiKey() {
        assertDoesNotThrow(() -> new NafruEmail("nafru_x"));
    }

    @Test
    void warnsOncePerClientOnDeprecationHeader() {
        Map<String, String> headers = Map.of(
                "deprecation", "true",
                "sunset", "Wed, 01 Jul 2027 00:00:00 GMT",
                "link", "<https://nafru.com/docs/sdk>; rel=\"deprecation\"");
        MockTransport mock = MockTransport.sequence(json(200, "{\"id\":\"e1\"}", headers), json(404, "", headers));
        NafruEmail nafru = mock.client(0);
        PrintStream original = System.err;
        ByteArrayOutputStream captured = new ByteArrayOutputStream();
        System.setErr(new PrintStream(captured, true, StandardCharsets.UTF_8));
        try {
            assertEquals("e1", nafru.emails().get("e1").id());
            assertThrows(NafruException.class, () -> nafru.emails().get("e2"));
        } finally {
            System.setErr(original);
        }
        assertEquals(
                "[nafru] Bu SDK sürümü (java " + NafruEmail.SDK_VERSION + ") kullanımdan kaldırıldı; lütfen güncelleyin."
                        + " Son tarih: Wed, 01 Jul 2027 00:00:00 GMT Ayrıntı: https://nafru.com/docs/sdk" + System.lineSeparator(),
                captured.toString(StandardCharsets.UTF_8));
    }
}
