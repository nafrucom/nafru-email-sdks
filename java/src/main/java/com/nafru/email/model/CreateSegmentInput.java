package com.nafru.email.model;

import java.util.Map;

public final class CreateSegmentInput extends Params<CreateSegmentInput> {
    public CreateSegmentInput(String name) { set("name", name); }
    /** Verilirse dinamik segment. */
    public CreateSegmentInput filter(Map<String, ?> filter) { return set("filter", filter); }
}
