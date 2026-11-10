package com.nafru.email.model;

public final class CreateApiKeyInput extends Params<CreateApiKeyInput> {
    public CreateApiKeyInput(String name) { set("name", name); }
    /** Varsayılan {@code full_access}. */
    public CreateApiKeyInput permission(String value) { return set("permission", value); }
    /** Yalnız {@code sending_access} ile: anahtarı bu alan adına kısıtlar. */
    public CreateApiKeyInput domainId(String value) { return set("domain_id", value); }
}
