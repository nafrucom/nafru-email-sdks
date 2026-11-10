package com.nafru.email;

import static org.junit.jupiter.api.Assertions.*;

import com.fasterxml.jackson.databind.JsonNode;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.Base64;
import javax.crypto.Mac;
import javax.crypto.spec.SecretKeySpec;
import org.junit.jupiter.api.Test;

class WebhookVerifierTest {
    private static final String SECRET = "whsec_" + Base64.getEncoder().encodeToString("0123456789abcdef0123456789abcdef".getBytes());
    private static final long NOW = 1_800_000_000_000L;
    private static final String TS = String.valueOf(NOW / 1000);
    private static final String BODY = "{\"type\":\"email.sent\",\"created_at\":\"2026-10-25T00:00:00Z\",\"data\":{}}";

    private static String sign(String id, String timestamp, String body) throws Exception {
        Mac mac = Mac.getInstance("HmacSHA256");
        mac.init(new SecretKeySpec(Base64.getDecoder().decode(SECRET.substring(6)), "HmacSHA256"));
        return "v1," + Base64.getEncoder().encodeToString(mac.doFinal((id + "." + timestamp + "." + body).getBytes(StandardCharsets.UTF_8)));
    }

    private static boolean verify(String body, String id, String ts, String signature, String secret) {
        return WebhookVerifier.verify(body, id, ts, signature, secret, 300, NOW);
    }

    @Test
    void sharedVector() throws Exception {
        JsonNode v = Json.MAPPER.readTree(Files.readString(Path.of("../webhook-test-vector.json")));
        long now = v.get("now_seconds").asLong() * 1000;
        String payload = v.get("payload").asText();
        assertTrue(WebhookVerifier.verify(payload, v.get("id").asText(), v.get("timestamp").asText(),
                v.get("signature").asText(), v.get("secret").asText(), 300, now));
        assertFalse(WebhookVerifier.verify(payload + " ", v.get("id").asText(), v.get("timestamp").asText(),
                v.get("signature").asText(), v.get("secret").asText(), 300, now));
    }

    @Test
    void acceptsValidAndOneOfManySignatures() throws Exception {
        String good = sign("msg_1", TS, BODY);
        assertTrue(verify(BODY, "msg_1", TS, good, SECRET));
        assertTrue(verify(BODY, "msg_1", TS, "v1,bozuk " + good + " v2,x", SECRET));
    }

    @Test
    void rejectsTamperedBodyIdOrKey() throws Exception {
        String signature = sign("msg_1", TS, BODY);
        assertFalse(verify(BODY + " ", "msg_1", TS, signature, SECRET));
        assertFalse(verify(BODY, "msg_2", TS, signature, SECRET));
        String other = "whsec_" + Base64.getEncoder().encodeToString("ffffffffffffffffffffffffffffffff".getBytes());
        assertFalse(verify(BODY, "msg_1", TS, signature, other));
    }

    @Test
    void rejectsOldOrBrokenTimestamp() throws Exception {
        String old = String.valueOf(NOW / 1000 - 301);
        assertFalse(verify(BODY, "msg_1", old, sign("msg_1", old, BODY), SECRET));
        assertFalse(verify(BODY, "msg_1", "abc", sign("msg_1", TS, BODY), SECRET));
    }

    @Test
    void missingHeadersAndFutureTimestampsAndSignatureCap() throws Exception {
        String good = sign("msg_1", TS, BODY);
        assertFalse(verify(BODY, "", TS, good, SECRET));
        assertFalse(verify(BODY, null, TS, good, SECRET));
        assertFalse(verify(BODY, "msg_1", "", good, SECRET));
        assertFalse(verify(BODY, "msg_1", TS, "", SECRET));
        assertFalse(verify(null, "msg_1", TS, good, SECRET));
        String future = String.valueOf(NOW / 1000 + 301);
        assertFalse(verify(BODY, "msg_1", future, sign("msg_1", future, BODY), SECRET));
        String many = "v1,x ".repeat(32) + good;
        assertFalse(verify(BODY, "msg_1", TS, many, SECRET));
        assertTrue(verify(BODY, "msg_1", TS, "v1,x ".repeat(31) + good, SECRET));
    }

    @Test
    void badSecretThrows() {
        IllegalArgumentException error = assertThrows(IllegalArgumentException.class, () -> verify(BODY, "a", TS, "v1,x", "sec"));
        assertTrue(error.getMessage().contains("whsec_"));
        assertThrows(IllegalArgumentException.class, () -> verify(BODY, "a", TS, "v1,x", "whsec_***"));
    }
}
