package com.nafru.email.model;

/** {@code content} (base64) ya da {@code path} (herkese açık https adresi) verilir; ikisi birlikte verilmez. */
public record Attachment(String content, String path, String filename, String contentType, String contentId) {
    public static Attachment fromContent(String filename, String base64) {
        return new Attachment(base64, null, filename, null, null);
    }

    public static Attachment fromPath(String url) {
        return new Attachment(null, url, null, null, null);
    }
}
