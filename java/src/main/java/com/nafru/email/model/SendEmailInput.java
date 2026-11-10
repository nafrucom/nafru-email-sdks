package com.nafru.email.model;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

public final class SendEmailInput extends EmailFields<SendEmailInput> {
    public SendEmailInput attachments(List<Attachment> attachments) { return set("attachments", attachments); }

    /** Şablonla gönderim: {@code html}/{@code text}/{@code attachments} ile birlikte verilmez. */
    public SendEmailInput template(String id, Map<String, ?> variables) {
        Map<String, Object> template = new LinkedHashMap<>();
        template.put("id", id);
        if (variables != null) template.put("variables", variables);
        return set("template", template);
    }
}
