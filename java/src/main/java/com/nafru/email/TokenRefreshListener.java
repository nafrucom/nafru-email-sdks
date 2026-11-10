package com.nafru.email;

import com.nafru.email.model.ConnectionTokens;

/**
 * Yenileme belirteci döndüğünde çağrılır; yeni değeri KALICI olarak yazmadan eskisi geçersizdir. İstisna fırlatırsa çağrı
 * {@code token_persist_failed} ile başarısız olur ve kayıt bir sonraki çağrıda yeniden denenir.
 */
@FunctionalInterface
public interface TokenRefreshListener {
    void onTokenRefresh(ConnectionTokens tokens) throws Exception;
}
