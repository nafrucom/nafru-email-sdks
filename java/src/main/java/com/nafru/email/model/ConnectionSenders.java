package com.nafru.email.model;

import java.util.List;

public record ConnectionSenders(List<SenderDomain> domains, String defaultFrom) {
    public record SenderDomain(String id, String name) {}
}
