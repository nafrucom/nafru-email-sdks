package com.nafru.email.model;

import java.util.Map;

/** {@code type}: {@code static} ya da {@code dynamic}; {@code object} yalnız {@code get} yanıtında dolu. */
public record Segment(String id, String object, String name, String createdAt, String type, Map<String, Object> filter)
        implements Identified {}
