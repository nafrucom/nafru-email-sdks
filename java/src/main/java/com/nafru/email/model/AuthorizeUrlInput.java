package com.nafru.email.model;

import java.util.List;

/**
 * @param redirectUri kayıtlı yönlendirme adresiyle birebir aynı olmalı
 * @param state CSRF koruması: istekten önce üretip oturumda saklayın, dönüşte karşılaştırın; zorunlu
 * @param loginHint müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir; {@code null} olabilir
 */
public record AuthorizeUrlInput(String redirectUri, String state, List<String> scopes, String loginHint) {
    public AuthorizeUrlInput(String redirectUri, String state, List<String> scopes) {
        this(redirectUri, state, scopes, null);
    }
}
