package com.nafru.email.model;

import java.util.List;

/**
 * @param missing hazır olmak için müşterinin tamamlaması gerekenler: {@code domain}, {@code sender}, {@code plan}
 * @param billingMode {@code customer_pays} ya da {@code app_pays}
 */
public record ConnectionStatus(
        String object,
        String id,
        boolean ready,
        List<String> missing,
        List<String> hints,
        List<String> scopes,
        String billingMode,
        String setupUrl,
        Workspace workspace) {
    public record Workspace(String name) {}
}
