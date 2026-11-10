package com.nafru.email;

import com.fasterxml.jackson.databind.JavaType;
import com.nafru.email.model.ConnectionSenders;
import com.nafru.email.model.ConnectionStatus;
import com.nafru.email.model.ConnectionTemplate;
import com.nafru.email.model.Email;
import com.nafru.email.model.IdResponse;
import com.nafru.email.model.ListEmailsQuery;
import com.nafru.email.model.ListResponse;
import com.nafru.email.model.SendEmailInput;

/**
 * Bir müşteri bağlantısı adına çağrı yapar. Her denemede belirteç yöneticisinden erişim belirteci alınır; 401 {@code invalid_token}
 * (süre dolmuş / yenilenmiş) ise bir kez yenileyip tekrar dener. Yönetim uçları (anahtar, alan adı, kişi, kampanya) yoktur.
 */
public final class NafruConnection {
    private final String id;
    private final Http.Caller call;
    private final Senders senders;
    private final ConnectionTemplates templates;
    private final ConnectionEmails emails;

    NafruConnection(String id, Http http, TokenManager tokens, String devOutbox) {
        this.id = id;
        this.call = new Http.Caller() {
            @Override
            public <T> T call(Http.Request request, JavaType type) {
                String[] used = new String[1];
                try {
                    return http.request(request, () -> used[0] = tokens.accessToken(), type);
                } catch (NafruException error) {
                    if (!"invalid_token".equals(error.getName()) || used[0] == null) throw error;
                    tokens.invalidate(used[0]);
                    return http.request(request, tokens::accessToken, type);
                }
            }
        };
        this.senders = new Senders(call);
        this.templates = new ConnectionTemplates(call);
        this.emails = new ConnectionEmails(new Emails(call, devOutbox));
    }

    public String id() { return id; }

    @Override
    public String toString() { return "NafruConnection[id=" + id + "]"; }

    /** {@code GET /connection}: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi. */
    public ConnectionStatus status() {
        return call.call(Http.Request.get("/connection"), ConnectionStatus.class);
    }

    public Senders senders() { return senders; }

    public ConnectionTemplates templates() { return templates; }

    public ConnectionEmails emails() { return emails; }

    public static final class Senders {
        private final Http.Caller call;

        Senders(Http.Caller call) { this.call = call; }

        public ConnectionSenders list() {
            return call.call(Http.Request.get("/senders"), ConnectionSenders.class);
        }
    }

    public static final class ConnectionTemplates {
        private final Http.Caller call;

        ConnectionTemplates(Http.Caller call) { this.call = call; }

        /** Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kopyası paketi gölgeler). */
        public ListResponse<ConnectionTemplate> list() {
            return call.call(Http.Request.get("/templates"), Json.listOf(ConnectionTemplate.class));
        }
    }

    /** Bağlantı adına gönderim ve okuma: yalnız {@code send}, {@code get}, {@code list}. */
    public static final class ConnectionEmails {
        private final Emails emails;

        ConnectionEmails(Emails emails) { this.emails = emails; }

        public IdResponse send(SendEmailInput input) { return emails.send(input); }
        public IdResponse send(SendEmailInput input, String idempotencyKey) { return emails.send(input, idempotencyKey); }
        public Email get(String id) { return emails.get(id); }
        public ListResponse<Email> list() { return emails.list(); }
        public ListResponse<Email> list(ListEmailsQuery query) { return emails.list(query); }
    }
}
