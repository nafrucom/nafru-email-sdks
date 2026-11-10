package com.nafru.email.model;

import com.nafru.email.Redact;

/** Tam anahtar ({@code token}) yalnız bir kez görünür. */
public record CreatedApiKey(String id, String token) {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "CreatedApiKey[id=" + id + ", token=" + Redact.mask(token) + "]";
    }
}
