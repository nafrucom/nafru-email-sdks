package com.nafru.email.model;

import java.util.List;
import java.util.Map;

/** Tekil ve toplu gönderimin ortak alanları. */
public abstract class EmailFields<S extends EmailFields<S>> extends Params<S> {
    /** {@code Ad <adres@alan.com>} ya da adres. Şablonla gönderimde isteğe bağlıdır (çalışma alanı varsayılanı). */
    public S from(String from) { return set("from", from); }
    public S to(String... to) { return addresses("to", to); }
    public S cc(String... cc) { return addresses("cc", cc); }
    public S bcc(String... bcc) { return addresses("bcc", bcc); }
    public S replyTo(String... replyTo) { return addresses("reply_to", replyTo); }
    public S subject(String subject) { return set("subject", subject); }
    public S html(String html) { return set("html", html); }
    public S text(String text) { return set("text", text); }
    public S headers(Map<String, String> headers) { return set("headers", headers); }
    public S tags(List<Tag> tags) { return set("tags", tags); }
    /** ISO 8601 ya da göreli ifade ({@code in 1 hour}). Geçmiş an hemen gönderir; en fazla 30 gün sonrası. */
    public S scheduledAt(String scheduledAt) { return set("scheduled_at", scheduledAt); }
}
