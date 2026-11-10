package com.nafru.email.model;

/** Uygulamanın müşteriden isteyebileceği izinler. */
public final class AppScope {
    public static final String EMAILS_SEND = "emails.send";
    public static final String EMAILS_READ = "emails.read";
    public static final String TEMPLATES_READ = "templates.read";
    public static final String DOMAINS_READ = "domains.read";
    public static final String SENDERS_READ = "senders.read";
    public static final String CONNECTION_READ = "connection.read";

    private AppScope() {}
}
