package com.nafru.email.model;

import java.util.List;

/** Şablon; {@code object} ve {@code previewText}'ten sonraki alanlar yalnız {@code get} yanıtında dolu. */
public record Template(
        String id,
        String object,
        String name,
        String alias,
        String type,
        String status,
        String subject,
        Integer currentVersion,
        boolean hasUnpublishedChanges,
        String publishedAt,
        String createdAt,
        String updatedAt,
        String previewText,
        String html,
        String text,
        Object design,
        Integer revision,
        List<TemplateVariable> variables,
        TemplateBrand brand) implements Identified {}
