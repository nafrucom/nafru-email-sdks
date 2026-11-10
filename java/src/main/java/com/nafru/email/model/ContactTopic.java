package com.nafru.email.model;

/** {@code status}: {@code opt_in}, {@code opt_out} ya da çift onay bekleyen {@code pending}. */
public record ContactTopic(String id, String name, String description, String subscription, String status)
        implements Identified {}
