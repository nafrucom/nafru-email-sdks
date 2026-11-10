package com.nafru.email.model;

public final class ListEmailsQuery extends Query<ListEmailsQuery> {
    public ListEmailsQuery status(String status) { return set("status", status); }
}
