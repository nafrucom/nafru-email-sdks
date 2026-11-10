package com.nafru.email.model;

import java.util.List;
import java.util.Map;

/**
 * Kampanya; {@code object} ve {@code from}'dan sonraki alanlar yalnız {@code get} yanıtında dolu. {@code triggerState}: {@code active},
 * {@code paused} ya da {@code null} (başlatılmadı); {@code parentId}: çalışma örneğinde şablonun kimliği.
 */
public record Broadcast(
        String id,
        String object,
        String name,
        String segmentId,
        String audienceId,
        String subject,
        String status,
        String createdAt,
        String scheduledAt,
        String sentAt,
        BroadcastRecurrence recurrence,
        String triggerState,
        String nextRunAt,
        String parentId,
        String from,
        List<String> replyTo,
        String previewText,
        String topicId,
        String templateId,
        String html,
        String text,
        Boolean openTracking,
        Boolean clickTracking,
        String finishedAt,
        String failureReason,
        Map<String, Object> data,
        BroadcastDataSource dataSource) implements Identified {}
