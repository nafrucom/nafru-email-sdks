package com.nafru.email;

/** 422 yanıtındaki alan ayrıntısı; {@code i18nTranslationKey} yoksa {@code null}. */
public record FieldError(String field, String message, String i18nTranslationKey) {}
