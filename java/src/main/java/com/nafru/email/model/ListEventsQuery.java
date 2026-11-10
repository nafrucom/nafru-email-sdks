package com.nafru.email.model;

public final class ListEventsQuery extends Query<ListEventsQuery> {
    /** Tam eşleşme; sistem olay adlarını ({@code email.opened}) da kabul eder. */
    public ListEventsQuery name(String name) { return set("name", name); }
    public ListEventsQuery contactId(String contactId) { return set("contact_id", contactId); }
    /** {@code contactId} ile birlikte verilmez. */
    public ListEventsQuery email(String email) { return set("email", email); }
}
