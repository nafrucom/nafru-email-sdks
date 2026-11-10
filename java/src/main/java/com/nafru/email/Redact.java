package com.nafru.email;

/** Gizli değerlerin (anahtar, belirteç, gizli) toString'de yerine yazılan metin. */
public final class Redact {
    public static final String SECRET = "[REDACTED]";

    private Redact() {}

    /** {@code null} kalır; aksi hâlde {@link #SECRET}. */
    public static String mask(String value) {
        return value == null ? null : SECRET;
    }
}
