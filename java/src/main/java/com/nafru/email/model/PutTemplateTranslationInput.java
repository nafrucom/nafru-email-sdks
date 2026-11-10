package com.nafru.email.model;

/** Bir dilin taslağı: API anahtarıyla yalnız {@code html} türü şablonda; locale ana dile indirgenir ({@code pt-BR} → {@code pt}). */
public final class PutTemplateTranslationInput extends Params<PutTemplateTranslationInput> {
    public PutTemplateTranslationInput(String html) { set("html", html); }
    public PutTemplateTranslationInput subject(String value) { return set("subject", value); }
    public PutTemplateTranslationInput previewText(String value) { return set("preview_text", value); }
    public PutTemplateTranslationInput text(String value) { return set("text", value); }
}
