package com.nafru.email.model;

import com.nafru.email.Redact;

public record ExchangeInput(String code, String codeVerifier, String redirectUri) {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "ExchangeInput[code=" + Redact.mask(code) + ", codeVerifier=" + Redact.mask(codeVerifier) + ", redirectUri=" + redirectUri + "]";
    }
}
