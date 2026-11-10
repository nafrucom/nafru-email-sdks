package com.nafru.email.model;

import com.nafru.email.Redact;

import java.util.List;

/**
 * @param connectionId {@code conn_…}: müşteri bağlantısının kalıcı kimliği
 * @param refreshToken şifreleyerek saklayın; her yenilemede değişir ({@code onTokenRefresh})
 */
public record ConnectionGrant(String connectionId, String refreshToken, List<String> scopes) {
    /** Gizli değer yazılmaz. */
    @Override
    public String toString() {
        return "ConnectionGrant[connectionId=" + connectionId + ", refreshToken=" + Redact.mask(refreshToken) + ", scopes=" + scopes + "]";
    }
}
