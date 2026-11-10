package com.nafru.email.model;

import java.util.List;
import java.util.Map;

public final class CreateContactInput extends Params<CreateContactInput> {
    public CreateContactInput(String email) { set("email", email); }
    public CreateContactInput firstName(String value) { return set("first_name", value); }
    public CreateContactInput lastName(String value) { return set("last_name", value); }
    public CreateContactInput unsubscribed(boolean value) { return set("unsubscribed", value); }
    /** ISO 639-1 ana dil kodu; bölgeli kod ({@code pt-BR}) sunucuda ana dile indirgenir. */
    public CreateContactInput locale(String value) { return set("locale", value); }
    /** Değerler metin, sayı ya da {@code null}. */
    public CreateContactInput properties(Map<String, ?> value) { return set("properties", value); }
    public CreateContactInput segments(String... segmentIds) {
        return set("segments", java.util.Arrays.stream(segmentIds).map(id -> Map.of("id", id)).toList());
    }
    public CreateContactInput topics(List<TopicSubscription> topics) { return set("topics", topics); }
}
