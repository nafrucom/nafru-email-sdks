package com.nafru.email.model;

import java.util.List;

/** E-posta; {@code object}, {@code html}, {@code text}, {@code tags} ve {@code events} yalnız {@code get} yanıtında dolu. */
public record Email(
        String id,
        String object,
        List<String> to,
        String from,
        String createdAt,
        String subject,
        List<String> bcc,
        List<String> cc,
        List<String> replyTo,
        String lastEvent,
        String scheduledAt,
        String messageId,
        String html,
        String text,
        List<Tag> tags,
        List<EmailEvent> events) implements Identified {}
