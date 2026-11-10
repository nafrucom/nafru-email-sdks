package com.nafru.email.model;

public final class UpdateTemplateInput extends Params<UpdateTemplateInput> {
    /** Eşzamanlı düzenleme denetimi: önceki okumadaki {@code revision}. */
    public UpdateTemplateInput revision(int value) { return set("revision", value); }
    public UpdateTemplateInput name(String value) { return set("name", value); }
    public UpdateTemplateInput alias(String value) { return set("alias", value); }
    public UpdateTemplateInput subject(String value) { return set("subject", value); }
    public UpdateTemplateInput previewText(String value) { return set("preview_text", value); }
    public UpdateTemplateInput html(String value) { return set("html", value); }
    public UpdateTemplateInput text(String value) { return set("text", value); }
    public UpdateTemplateInput brand(TemplateBrand value) { return set("brand", value); }
}
