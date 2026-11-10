package com.nafru.email.model;

import java.util.Map;

public final class UpdateContactInput extends Params<UpdateContactInput> {
    public UpdateContactInput firstName(String value) { return set("first_name", value); }
    public UpdateContactInput lastName(String value) { return set("last_name", value); }
    public UpdateContactInput unsubscribed(boolean value) { return set("unsubscribed", value); }
    public UpdateContactInput locale(String value) { return set("locale", value); }
    public UpdateContactInput properties(Map<String, ?> value) { return set("properties", value); }
}
