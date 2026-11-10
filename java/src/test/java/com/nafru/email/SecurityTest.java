package com.nafru.email;

import static com.nafru.email.MockTransport.json;
import static com.nafru.email.MockTransport.ok;
import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.BroadcastDataSource;
import com.nafru.email.model.ConnectionGrant;
import com.nafru.email.model.CreatedApiKey;
import com.nafru.email.model.ExchangeInput;
import com.nafru.email.model.SendEmailInput;
import java.net.http.HttpClient;
import java.time.Duration;
import java.util.List;
import java.util.Map;
import org.junit.jupiter.api.Test;

class SecurityTest {
    private static final SendEmailInput EMAIL = new SendEmailInput().from("a@x.test").to("b@x.test").subject("s").text("t");

    @Test
    void httpOnlyAllowedForLoopback() {
        for (String url : List.of("http://localhost:48787/api", "http://api.localhost", "http://127.0.0.1/api", "http://[::1]:8080/api",
                "https://email.example.com/api")) {
            assertDoesNotThrow(() -> NafruEmail.builder().apiKey("k").baseUrl(url).build(), url);
        }
        for (String url : List.of("http://email.example.com/api", "http://localhost.evil.com", "ftp://localhost", "http://10.0.0.1")) {
            IllegalArgumentException error = assertThrows(IllegalArgumentException.class,
                    () -> NafruEmail.builder().apiKey("k").baseUrl(url).build(), url);
            assertTrue(error.getMessage().contains("https"));
        }
        assertThrows(IllegalArgumentException.class,
                () -> NafruConnect.builder().clientId("a").clientSecret("s").webUrl("http://web.example.com").build());
        assertThrows(IllegalArgumentException.class,
                () -> NafruConnect.builder().clientId("a").clientSecret("s").baseUrl("http://email.example.com/api").build());
    }

    @Test
    void redirectIsAnErrorAndNotRetried() {
        MockTransport mock = MockTransport.sequence(json(302, "", Map.of("location", "https://evil.test/")));
        NafruException error = assertThrows(NafruException.class, () -> mock.client(2).emails().get("e1"));
        assertEquals("unexpected_redirect", error.getName());
        assertEquals(302, error.getStatusCode());
        assertEquals(1, mock.calls.size());
        assertThrows(IllegalArgumentException.class,
                () -> new HttpClientTransport(HttpClient.newBuilder().followRedirects(HttpClient.Redirect.NORMAL).build()));
    }

    @Test
    void rejectsDotAndEmptyPathSegments() {
        MockTransport mock = MockTransport.sequence(ok("{}"));
        NafruEmail nafru = mock.client(0);
        for (String id : new String[] {"", ".", "..", null}) {
            assertEquals("invalid_argument", assertThrows(NafruException.class, () -> nafru.emails().get(id)).getName());
        }
        assertEquals("invalid_argument",
                assertThrows(NafruException.class, () -> nafru.contacts().segments().add("c1", "..")).getName());
        assertTrue(mock.calls.isEmpty());
        nafru.emails().get("..x");
        assertEquals("http://api.localhost/emails/..x", mock.calls.get(0).url());
    }

    @Test
    void rejectsHeaderInjectionInIdempotencyKey() {
        MockTransport mock = MockTransport.sequence(ok("{\"id\":\"e1\"}"));
        NafruEmail nafru = mock.client(0);
        for (String key : new String[] {"", "a\r\nX-Evil: 1", "a\nb", "a\u0000b", "a\tb"}) {
            assertEquals("invalid_argument", assertThrows(NafruException.class, () -> nafru.emails().send(EMAIL, key)).getName());
        }
        assertTrue(mock.calls.isEmpty());
    }

    @Test
    void oversizedResponseIsRejected() {
        MockTransport mock = MockTransport.sequence(ok("x".repeat(Http.MAX_RESPONSE_BYTES + 1)));
        assertEquals("response_too_large", assertThrows(NafruException.class, () -> mock.client(0).emails().get("e1")).getName());
    }

    @Test
    void secretsAreRedactedInToString() {
        String apiKey = "nafru_live_supersecret";
        String text = String.join(" ",
                new NafruEmail(apiKey).toString(),
                NafruConnect.builder().clientId("app_x").clientSecret("nfs_topsecret").build().toString(),
                new ConnectionGrant("conn_1", "nfr_refreshsecret", List.of("emails.send")).toString(),
                new TokenManager.TokenPayload("nfa_accesssecret", "nfr_refreshsecret", 3600, "conn_1", List.of()).toString(),
                new CreatedApiKey("k1", apiKey).toString(),
                new ExchangeInput("nfc_codesecret", "verifiersecret", "https://x.test/cb").toString(),
                new BroadcastDataSource.Webhook("https://x.test/t", "whsec_secret").toString(),
                new Transport.Request("POST", "https://x.test/oauth/token", Map.of("authorization", "Bearer " + apiKey),
                        "{\"client_secret\":\"nfs_topsecret\"}", Duration.ofSeconds(1)).toString());
        for (String secret : List.of("supersecret", "topsecret", "refreshsecret", "accesssecret", "codesecret", "verifiersecret", "whsec_secret")) {
            assertFalse(text.contains(secret), secret + " sızdı: " + text);
        }
        assertTrue(text.contains("[REDACTED]"));
        assertTrue(text.contains("conn_1"));
    }

    @Test
    void errorsNeverContainTheKey() {
        MockTransport mock = new MockTransport(request -> { throw new java.io.IOException("bağlantı reddedildi"); });
        NafruEmail nafru = NafruEmail.builder().apiKey("nafru_live_supersecret").baseUrl("http://localhost").transport(mock)
                .maxRetries(0).devOutbox(false).build();
        NafruException error = assertThrows(NafruException.class, () -> nafru.emails().get("e1"));
        assertFalse(error.toString().contains("supersecret"));
    }
}
