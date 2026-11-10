package com.nafru.email.model;

import com.nafru.email.Redact;

public record ConnectionTokens(String refreshToken) {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "ConnectionTokens[refreshToken=" + Redact.mask(refreshToken) + "]";
    }
}
