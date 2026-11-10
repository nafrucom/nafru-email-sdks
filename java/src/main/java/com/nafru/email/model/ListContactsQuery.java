package com.nafru.email.model;

public final class ListContactsQuery extends Query<ListContactsQuery> {
    /** E-posta, ad ya da soyad içinde arar. */
    public ListContactsQuery search(String search) { return set("search", search); }
}
