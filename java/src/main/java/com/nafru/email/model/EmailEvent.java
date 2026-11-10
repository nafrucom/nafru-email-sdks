package com.nafru.email.model;

import java.util.Map;

public record EmailEvent(String id, String type, String createdAt, Map<String, Object> detail) {}
