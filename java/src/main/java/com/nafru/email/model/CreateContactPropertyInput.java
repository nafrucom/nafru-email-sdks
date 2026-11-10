package com.nafru.email.model;

public final class CreateContactPropertyInput extends Params<CreateContactPropertyInput> {
    /** {@code type}: {@code string} ya da {@code number}. */
    public CreateContactPropertyInput(String key, String type) {
        set("key", key);
        set("type", type);
    }

    public CreateContactPropertyInput fallbackValue(Object value) { return set("fallback_value", value); }
}
