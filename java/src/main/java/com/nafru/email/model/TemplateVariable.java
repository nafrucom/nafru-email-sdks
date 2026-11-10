package com.nafru.email.model;

/** Şablonda kullanılan değişken: {@code {{{AD}}}} ya da {@code {{{AD|yedek}}}}; {@code fallbackValue} yoksa {@code null}. */
public record TemplateVariable(String key, String type, String fallbackValue) {}
