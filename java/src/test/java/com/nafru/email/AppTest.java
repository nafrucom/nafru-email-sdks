package com.nafru.email;

import static com.nafru.email.MockTransport.json;
import static com.nafru.email.MockTransport.ok;
import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.AuthorizeUrl;
import com.nafru.email.model.AuthorizeUrlInput;
import com.nafru.email.model.ConnectionGrant;
import com.nafru.email.model.ExchangeInput;
import com.nafru.email.model.SendEmailInput;
import java.net.URI;
import java.net.URLDecoder;
import java.nio.charset.StandardCharsets;
import java.security.MessageDigest;
import java.util.ArrayList;
import java.util.Base64;
import java.util.Collections;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.concurrent.ExecutorService;
import java.util.concurrent.Executors;
import java.util.concurrent.Future;
import java.util.concurrent.atomic.AtomicInteger;
import org.junit.jupiter.api.Test;

class AppTest {
    private static final String GRANT_ERROR = "{\"statusCode\":400,\"name\":\"invalid_grant\",\"message\":\"invalid\"}";

    private static String token(int n) {
        return "{\"access_token\":\"nfa_" + n + "\",\"refresh_token\":\"nfr_" + n + "\",\"token_type\":\"Bearer\","
                + "\"expires_in\":3600,\"connection_id\":\"conn_1\",\"scopes\":[\"emails.send\"]}";
    }

    private static NafruConnect client(MockTransport mock) {
        return NafruConnect.builder().clientId("app_x").clientSecret("nfs_secret").baseUrl("http://api.localhost/")
                .webUrl("http://web.localhost").transport(mock).maxRetries(0).devOutbox(false).build();
    }

    private static boolean isToken(Transport.Request call) { return call.url().endsWith("/oauth/token"); }

    private static List<Transport.Request> api(MockTransport mock) {
        return mock.calls.stream().filter(call -> !call.url().contains("/oauth/")).toList();
    }

    private static Map<String, String> params(String url) {
        Map<String, String> out = new LinkedHashMap<>();
        for (String pair : URI.create(url).getRawQuery().split("&")) {
            String[] kv = pair.split("=", 2);
            out.put(kv[0], URLDecoder.decode(kv[1], StandardCharsets.UTF_8));
        }
        return out;
    }

    @Test
    void pkceVerifierAndChallenge() throws Exception {
        String[] pkce = NafruConnect.createPkce();
        assertTrue(pkce[0].matches("^[A-Za-z0-9_-]{43}$"));
        byte[] digest = MessageDigest.getInstance("SHA-256").digest(pkce[0].getBytes(StandardCharsets.US_ASCII));
        assertEquals(Base64.getUrlEncoder().withoutPadding().encodeToString(digest), pkce[1]);
        assertNotEquals(pkce[0], NafruConnect.createPkce()[0]);
    }

    @Test
    void authorizeUrlBuildsConsentUrlAndRequiresStateAndScopes() {
        NafruConnect nafru = client(MockTransport.sequence(ok("{}")));
        AuthorizeUrl result = nafru.authorizeUrl(
                new AuthorizeUrlInput("https://scout.test/cb", "st1", List.of("emails.send", "templates.read"), "a@b.co"));
        assertTrue(result.url().startsWith("http://web.localhost/connect?"));
        Map<String, String> params = params(result.url());
        assertEquals("app_x", params.get("client_id"));
        assertEquals("https://scout.test/cb", params.get("redirect_uri"));
        assertEquals("st1", params.get("state"));
        assertEquals("emails.send templates.read", params.get("scope"));
        assertEquals("S256", params.get("code_challenge_method"));
        assertEquals("a@b.co", params.get("login_hint"));
        assertTrue(params.get("code_challenge").matches("^[A-Za-z0-9_-]{43}$"));
        assertTrue(result.codeVerifier().matches("^[A-Za-z0-9_-]{43}$"));
        assertThrows(IllegalArgumentException.class,
                () -> nafru.authorizeUrl(new AuthorizeUrlInput("x", "", List.of("emails.send"))));
        assertThrows(IllegalArgumentException.class, () -> nafru.authorizeUrl(new AuthorizeUrlInput("x", "s", List.of())));
    }

    @Test
    void webUrlDefaultsToBaseUrlWithoutApi() {
        NafruConnect nafru = NafruConnect.builder().clientId("a").clientSecret("s").baseUrl("https://email.x.test/api/")
                .transport(MockTransport.sequence(ok("{}"))).build();
        assertTrue(nafru.authorizeUrl(new AuthorizeUrlInput("r", "s", List.of("emails.send")))
                .url().startsWith("https://email.x.test/connect?"));
    }

    @Test
    void defaultBaseUrlAndDerivedWebUrl() {
        MockTransport mock = MockTransport.sequence(ok(token(1)));
        NafruConnect nafru = NafruConnect.builder().clientId("a").clientSecret("s").transport(mock).build();
        assertTrue(nafru.authorizeUrl(new AuthorizeUrlInput("r", "s", List.of("emails.send")))
                .url().startsWith("https://email.nafru.com/connect?"));
        nafru.exchange(new ExchangeInput("c", "v", "r"));
        assertEquals("https://email.nafru.com/api/oauth/token", mock.calls.get(0).url());
    }

    @Test
    void exchangeSendsCredentialsInBodyWithoutAuthorization() {
        MockTransport mock = MockTransport.sequence(ok(token(1)));
        ConnectionGrant grant = client(mock).exchange(new ExchangeInput("nfc_1", "v".repeat(43), "https://scout.test/cb"));
        assertEquals(new ConnectionGrant("conn_1", "nfr_1", List.of("emails.send")), grant);
        Transport.Request call = mock.calls.get(0);
        assertEquals("http://api.localhost/oauth/token", call.url());
        assertNull(call.headers().get("authorization"));
        assertEquals("authorization_code", MockTransport.body(call).get("grant_type").asText());
        assertEquals("nfs_secret", MockTransport.body(call).get("client_secret").asText());
        assertEquals("nfc_1", MockTransport.body(call).get("code").asText());
    }

    @Test
    void exchangeErrorThrows() {
        NafruConnect nafru = client(MockTransport.sequence(json(400, GRANT_ERROR)));
        NafruException error = assertThrows(NafruException.class, () -> nafru.exchange(new ExchangeInput("c", "v", "r")));
        assertEquals(400, error.getStatusCode());
        assertEquals("invalid_grant", error.getName());
    }

    @Test
    void revokeSendsRefreshToken() {
        MockTransport mock = MockTransport.sequence(ok("{}"));
        client(mock).revoke("nfr_1");
        assertEquals("{\"client_id\":\"app_x\",\"client_secret\":\"nfs_secret\",\"token\":\"nfr_1\"}", mock.calls.get(0).body());
    }

    @Test
    void firstCallRefreshesPersistsAndUsesAccessToken() {
        MockTransport mock = new MockTransport(call -> isToken(call) ? ok(token(1)) : ok("{\"object\":\"connection\",\"id\":\"conn_1\",\"ready\":true}"));
        List<String> saved = new ArrayList<>();
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> saved.add(tokens.refreshToken()));
        assertTrue(connection.status().ready());
        assertEquals(List.of("nfr_1"), saved);
        assertEquals("nfr_0", MockTransport.body(mock.calls.get(0)).get("refresh_token").asText());
        assertEquals("http://api.localhost/connection", api(mock).get(0).url());
        assertEquals("Bearer nfa_1", api(mock).get(0).headers().get("authorization"));
    }

    @Test
    void concurrentCallsShareOneRefresh() throws Exception {
        MockTransport mock = new MockTransport(call -> {
            if (isToken(call)) {
                Thread.sleep(50);
                return ok(token(1));
            }
            return ok("{\"ready\":true}");
        });
        List<String> saved = Collections.synchronizedList(new ArrayList<>());
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> saved.add(tokens.refreshToken()));
        ExecutorService pool = Executors.newFixedThreadPool(5);
        try {
            List<Future<Boolean>> results = new ArrayList<>();
            for (int i = 0; i < 5; i++) results.add(pool.submit(() -> connection.status().ready()));
            for (Future<Boolean> result : results) assertTrue(result.get());
        } finally {
            pool.shutdown();
        }
        assertEquals(1, mock.calls.stream().filter(AppTest::isToken).count());
        assertEquals(List.of("nfr_1"), saved);
        connection.status();
        assertEquals(1, mock.calls.stream().filter(AppTest::isToken).count());
    }

    @Test
    void invalidTokenRefreshesOnceAndRetries() {
        AtomicInteger refreshes = new AtomicInteger();
        MockTransport mock = new MockTransport(call -> {
            if (isToken(call)) return ok(token(refreshes.incrementAndGet()));
            return "Bearer nfa_1".equals(call.headers().get("authorization"))
                    ? json(401, "{\"statusCode\":401,\"name\":\"invalid_token\",\"message\":\"expired\"}")
                    : ok("{\"ready\":true}");
        });
        List<String> saved = new ArrayList<>();
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> saved.add(tokens.refreshToken()));
        assertTrue(connection.status().ready());
        assertEquals(2, refreshes.get());
        assertEquals(List.of("nfr_1", "nfr_2"), saved);
        assertEquals("nfr_1", MockTransport.body(mock.calls.stream().filter(AppTest::isToken).toList().get(1)).get("refresh_token").asText());
        assertEquals(List.of("Bearer nfa_1", "Bearer nfa_2"), api(mock).stream().map(c -> c.headers().get("authorization")).toList());
    }

    @Test
    void rejectedRefreshBecomesConnectionRevoked() {
        MockTransport mock = MockTransport.sequence(json(400, GRANT_ERROR));
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> {});
        assertEquals("connection_revoked", assertThrows(NafruException.class, connection::status).getName());
        assertTrue(api(mock).isEmpty());
        MockTransport forbidden = MockTransport.sequence(json(403, "{\"message\":\"no\"}"));
        assertEquals("connection_revoked",
                assertThrows(NafruException.class, client(forbidden).connection("c", "r", t -> {})::status).getName());
    }

    @Test
    void persistFailureIsReportedThenRetriedWithoutNewRefresh() {
        MockTransport mock = new MockTransport(call -> isToken(call) ? ok(token(1)) : ok("{\"ready\":true}"));
        List<String> saved = new ArrayList<>();
        AtomicInteger failures = new AtomicInteger(1);
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> {
            if (failures.getAndDecrement() > 0) throw new IllegalStateException("disk dolu");
            saved.add(tokens.refreshToken());
        });
        NafruException error = assertThrows(NafruException.class, connection::status);
        assertEquals("token_persist_failed", error.getName());
        assertTrue(error.getMessage().contains("disk dolu"));
        assertTrue(connection.status().ready());
        assertEquals(List.of("nfr_1"), saved);
        assertEquals(1, mock.calls.stream().filter(AppTest::isToken).count());
    }

    @Test
    void connectionEndpoints() {
        MockTransport mock = new MockTransport(call -> isToken(call) ? ok(token(1)) : ok("{\"id\":\"e1\",\"data\":[]}"));
        NafruConnection connection = client(mock).connection("conn_1", "nfr_0", tokens -> {});
        connection.senders().list();
        connection.templates().list();
        connection.emails().send(new SendEmailInput().from("a@b.co").to("c@d.co").subject("s").html("<p>x</p>"), "k1");
        connection.emails().get("e1");
        connection.emails().list();
        assertEquals(List.of("GET /senders", "GET /templates", "POST /emails", "GET /emails/e1", "GET /emails"),
                api(mock).stream().map(c -> c.method() + " " + URI.create(c.url()).getPath()).toList());
        assertEquals("k1", api(mock).get(2).headers().get("idempotency-key"));
    }

    @Test
    void serverErrorPropagates() {
        MockTransport mock = new MockTransport(call -> isToken(call) ? ok(token(1))
                : json(403, "{\"statusCode\":403,\"name\":\"insufficient_scope\",\"message\":\"scope\"}"));
        NafruException error = assertThrows(NafruException.class,
                () -> client(mock).connection("conn_1", "nfr_0", t -> {}).templates().list());
        assertEquals(403, error.getStatusCode());
        assertEquals("insufficient_scope", error.getName());
    }
}
