package com.nafru.email.model;

import java.util.List;

public final class UpdateWebhookInput extends Params<UpdateWebhookInput> {
    public UpdateWebhookInput endpoint(String value) { return set("endpoint", value); }
    public UpdateWebhookInput events(List<String> value) { return set("events", value); }
    /** enabled ya da disabled. */
    public UpdateWebhookInput status(String value) { return set("status", value); }
}
