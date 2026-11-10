package com.nafru.email.model;

/**
 * {@code {{{data.*}}}} değişkenlerinin kaynağı. {@code url}: gönderim anında {@code GET} (https, ≤ 256 KB JSON nesne, 10 sn);
 * {@code webhook}: imzalı tetik ucu. Başlık alanlarında çağrılmayan ayarlayıcı mevcut değeri korur, {@code null} siler.
 */
public final class BroadcastDataSourceInput extends Params<BroadcastDataSourceInput> {
    private BroadcastDataSourceInput(String type) { set("type", type); }

    public static BroadcastDataSourceInput manual() { return new BroadcastDataSourceInput("manual"); }

    public static BroadcastDataSourceInput url(String url) { return new BroadcastDataSourceInput("url").set("url", url); }

    public static BroadcastDataSourceInput webhook() { return new BroadcastDataSourceInput("webhook"); }

    /** Yalnız {@code url}. */
    public BroadcastDataSourceInput headerName(String value) { return set("header_name", value); }

    /** Yalnız {@code url}. */
    public BroadcastDataSourceInput headerValue(String value) { return set("header_value", value); }

    /** Yalnız {@code webhook}: gizli anahtarı yeniler. */
    public BroadcastDataSourceInput regenerateSecret(boolean value) { return set("regenerate_secret", value); }
}
