package com.nafru.email.model;

public final class CreateTemplateInput extends Params<CreateTemplateInput> {
    public CreateTemplateInput(String name, String html) {
        set("name", name);
        set("html", html);
    }

    public CreateTemplateInput alias(String value) { return set("alias", value); }
    public CreateTemplateInput subject(String value) { return set("subject", value); }
    public CreateTemplateInput previewText(String value) { return set("preview_text", value); }
    public CreateTemplateInput text(String value) { return set("text", value); }
    /** Varsayılan {@code none}: HTML olduğu gibi kalır. */
    public CreateTemplateInput brand(TemplateBrand value) { return set("brand", value); }
}
