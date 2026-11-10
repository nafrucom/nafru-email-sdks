package com.nafru.email.model;

import com.fasterxml.jackson.annotation.JsonProperty;
import com.fasterxml.jackson.annotation.JsonPropertyOrder;
import com.fasterxml.jackson.annotation.JsonSubTypes;
import com.fasterxml.jackson.annotation.JsonTypeInfo;
import java.util.List;

/**
 * Tekrar kuralı; saat ({@code HH:MM}) çalışma alanının saat dilimindedir. {@code Weekly.days}: 0 = pazar … 6 = cumartesi;
 * {@code Monthly.day}: 1–31 (ay kısaysa son gün); {@code Interval.everyDays}: 1–365. Bilinmeyen tür {@link Unknown} olarak okunur.
 */
// EXISTING_PROPERTY: tür, değer haritada (statik tür Object) dizildiğinde de type() ile yazılır.
@JsonTypeInfo(use = JsonTypeInfo.Id.NAME, include = JsonTypeInfo.As.EXISTING_PROPERTY, property = "type", defaultImpl = BroadcastRecurrence.Unknown.class)
@JsonSubTypes({
    @JsonSubTypes.Type(value = BroadcastRecurrence.Weekly.class, name = "weekly"),
    @JsonSubTypes.Type(value = BroadcastRecurrence.Monthly.class, name = "monthly"),
    @JsonSubTypes.Type(value = BroadcastRecurrence.Interval.class, name = "interval")
})
@JsonPropertyOrder("type")
public sealed interface BroadcastRecurrence {
    @JsonProperty("type")
    String type();

    record Weekly(List<Integer> days, String time) implements BroadcastRecurrence {
        @Override public String type() { return "weekly"; }
    }

    record Monthly(int day, String time) implements BroadcastRecurrence {
        @Override public String type() { return "monthly"; }
    }

    record Interval(int everyDays, String time) implements BroadcastRecurrence {
        @Override public String type() { return "interval"; }
    }

    /** SDK'nın henüz tanımadığı tür (yalnız yanıtlarda). */
    record Unknown() implements BroadcastRecurrence {
        @Override public String type() { return "unknown"; }
    }
}
