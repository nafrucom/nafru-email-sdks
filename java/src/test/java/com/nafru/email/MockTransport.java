package com.nafru.email;

import com.fasterxml.jackson.databind.JsonNode;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.List;
import java.util.Map;

/** Sahte taşıyıcı: yanıtları sırayla verir, son yanıtı tekrarlar; çağrıları kaydeder. */
final class MockTransport implements Transport {
    interface Route {
        Response handle(Request request) throws IOException, InterruptedException;
    }

    final List<Request> calls = Collections.synchronizedList(new ArrayList<>());
    private final Route route;

    MockTransport(Route route) { this.route = route; }

    static MockTransport sequence(Response... responses) {
        int[] index = {0};
        return new MockTransport(request -> responses[Math.min(index[0]++, responses.length - 1)]);
    }

    static Response json(int status, String body) { return json(status, body, Map.of()); }

    static Response json(int status, String body, Map<String, String> headers) {
        return new Response(status, headers, body);
    }

    static Response ok(String body) { return json(200, body); }

    static JsonNode body(Request request) {
        try {
            return request.body() == null ? null : Json.MAPPER.readTree(request.body());
        } catch (IOException e) {
            throw new AssertionError(e);
        }
    }

    @Override
    public Response send(Request request) throws IOException, InterruptedException {
        calls.add(request);
        return route.handle(request);
    }

    NafruEmail client(int maxRetries) {
        return NafruEmail.builder().apiKey("key_test").baseUrl("http://api.localhost/").transport(this).maxRetries(maxRetries)
                .devOutbox(false).build();
    }
}
