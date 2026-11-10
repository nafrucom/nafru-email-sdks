package com.nafru.email.model;

import com.nafru.email.Redact;

/** {@code codeVerifier}: yalnız bu bağlanma denemesi için; {@code exchange}'e kadar sunucunuzda (oturumda) saklayın, tarayıcıya vermeyin. */
public record AuthorizeUrl(String url, String codeVerifier) {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "AuthorizeUrl[url=" + url + ", codeVerifier=" + Redact.mask(codeVerifier) + "]";
    }
}
