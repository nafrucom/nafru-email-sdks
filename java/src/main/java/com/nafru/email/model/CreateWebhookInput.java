package com.nafru.email.model;

import java.util.List;

public final class CreateWebhookInput extends Params<CreateWebhookInput> {
    /** {@code endpoint}: herkese açık https adresi; {@code events}: {@code email.sent}, {@code contact.created}, … */
    public CreateWebhookInput(String endpoint, List<String> events) {
        set("endpoint", endpoint);
        set("events", events);
    }
}
