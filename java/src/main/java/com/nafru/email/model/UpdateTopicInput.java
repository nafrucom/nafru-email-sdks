package com.nafru.email.model;

public final class UpdateTopicInput extends Params<UpdateTopicInput> {
    public UpdateTopicInput name(String value) { return set("name", value); }
    public UpdateTopicInput description(String value) { return set("description", value); }
    public UpdateTopicInput visibility(String value) { return set("visibility", value); }
    public UpdateTopicInput doubleOptIn(boolean value) { return set("double_opt_in", value); }
}
