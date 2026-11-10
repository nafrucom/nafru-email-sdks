package com.nafru.email.model;

public final class UpdateDomainInput extends Params<UpdateDomainInput> {
    public UpdateDomainInput openTracking(boolean value) { return set("open_tracking", value); }
    public UpdateDomainInput clickTracking(boolean value) { return set("click_tracking", value); }
    public UpdateDomainInput tls(String tls) { return set("tls", tls); }
    /** {@code null}: izleme alt alan adını kaldırır. */
    public UpdateDomainInput trackingSubdomain(String value) { return set("tracking_subdomain", value); }
}
