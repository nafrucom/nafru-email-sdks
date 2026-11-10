package com.nafru.email.model;

/** {@code source}: {@code workspace} ya da {@code pack}. */
public record ConnectionTemplate(String key, String name, String source, boolean customizedFromPack) {}
