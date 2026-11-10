package com.nafru.email.model;

public final class CreateTopicInput extends Params<CreateTopicInput> {
    /** {@code defaultSubscription}: {@code opt_in} ya da {@code opt_out}. */
    public CreateTopicInput(String name, String defaultSubscription) {
        set("name", name);
        set("default_subscription", defaultSubscription);
    }

    public CreateTopicInput description(String value) { return set("description", value); }
    /** {@code public} ya da {@code private}. */
    public CreateTopicInput visibility(String value) { return set("visibility", value); }
    public CreateTopicInput doubleOptIn(boolean value) { return set("double_opt_in", value); }
}
