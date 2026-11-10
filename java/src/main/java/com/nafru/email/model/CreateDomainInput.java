package com.nafru.email.model;

public final class CreateDomainInput extends Params<CreateDomainInput> {
    public CreateDomainInput(String name) { set("name", name); }
    public CreateDomainInput region(String region) { return set("region", region); }
    public CreateDomainInput openTracking(boolean value) { return set("open_tracking", value); }
    public CreateDomainInput clickTracking(boolean value) { return set("click_tracking", value); }
    /** {@code opportunistic} ya da {@code enforced}. */
    public CreateDomainInput tls(String tls) { return set("tls", tls); }
    /** Örn. {@code track} → {@code track.<alan-adı>}. */
    public CreateDomainInput trackingSubdomain(String value) { return set("tracking_subdomain", value); }
}
