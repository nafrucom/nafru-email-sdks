package com.nafru.email;

import com.fasterxml.jackson.core.JsonProcessingException;
import com.nafru.email.model.IdResponse;
import java.io.IOException;
import java.io.UncheckedIOException;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.security.SecureRandom;
import java.time.ZoneOffset;
import java.time.ZonedDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Map;
import java.util.regex.Pattern;

/** Geliştirme ortamında e-postayı göndermeden dosyaya yazar. */
final class DevOutbox {
    static final String DEFAULT_DIR = ".nafru/emails";
    private static final SecureRandom RANDOM = new SecureRandom();
    private static final DateTimeFormatter STAMP = DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH-mm-ss-SSS'Z'");

    private DevOutbox() {}

    /** Açıkça verilmediyse: yalnız {@code NODE_ENV=development} iken {@code .nafru/emails}; aksi hâlde gerçek gönderim ({@code null}). */
    static String resolve(boolean set, String dir, String nodeEnv) {
        if (set) return dir;
        return "development".equals(nodeEnv) ? DEFAULT_DIR : null;
    }

    private static String list(Object value) {
        if (value == null) return "";
        if (value instanceof List<?> items) return String.join(", ", items.stream().map(String::valueOf).toList());
        return String.valueOf(value);
    }

    private static String escapeHtml(String text) {
        return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace("\"", "&quot;");
    }

    // shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
    static String htmlToText(String html) {
        return Pattern.compile("<(style|script)[\\s\\S]*?</\\1>", Pattern.CASE_INSENSITIVE).matcher(html).replaceAll("")
                .replaceAll("(?i)<br\\s*/?>|</(p|div|h[1-6]|li|tr)>", "\n")
                .replaceAll("<[^>]+>", "")
                .replace("&nbsp;", " ")
                .replace("&lt;", "<")
                .replace("&gt;", ">")
                .replace("&quot;", "\"")
                .replace("&amp;", "&")
                .replaceAll("\n{3,}", "\n\n")
                .trim();
    }

    private static String bodyText(Map<String, Object> email) {
        if (email.get("text") instanceof String text && !text.isEmpty()) return text;
        if (email.get("html") instanceof String html && !html.isEmpty()) return htmlToText(html);
        if (email.get("template") instanceof Map<?, ?> template) {
            Object variables = template.get("variables") != null ? template.get("variables") : Map.of();
            try {
                return "[şablon " + template.get("id") + "]\n"
                        + Json.MAPPER.writerWithDefaultPrettyPrinter().writeValueAsString(variables);
            } catch (JsonProcessingException e) {
                return "[şablon " + template.get("id") + "]";
            }
        }
        return "";
    }

    /** E-postayı göndermeden {@code dir} altına {@code .txt} ve {@code .html} olarak yazar, yolu ve düz metni konsola basar. */
    static IdResponse write(String dir, Map<String, Object> email) {
        StringBuilder random = new StringBuilder();
        for (int i = 0; i < 6; i++) random.append(Character.forDigit(RANDOM.nextInt(36), 36));
        String id = "dev_" + Long.toString(System.currentTimeMillis(), 36) + random;
        Path folder = Path.of(dir).toAbsolutePath();
        Path base = folder.resolve(ZonedDateTime.now(ZoneOffset.UTC).format(STAMP) + "-" + id);

        List<String> headers = new ArrayList<>();
        headers.add("From: " + list(email.get("from")));
        headers.add("To: " + list(email.get("to")));
        if (email.get("cc") != null) headers.add("Cc: " + list(email.get("cc")));
        if (email.get("bcc") != null) headers.add("Bcc: " + list(email.get("bcc")));
        if (email.get("reply_to") != null) headers.add("Reply-To: " + list(email.get("reply_to")));
        headers.add("Subject: " + list(email.get("subject")));
        if (email.get("scheduled_at") != null) headers.add("Scheduled-At: " + email.get("scheduled_at"));
        String body = bodyText(email);
        String text = String.join("\n", headers) + "\n\n" + body + "\n";
        String html = email.get("html") instanceof String h ? h : "<pre>" + escapeHtml(body) + "</pre>";

        Path txtPath = Path.of(base + ".txt");
        Path htmlPath = Path.of(base + ".html");
        try {
            Files.createDirectories(folder);
            Files.writeString(txtPath, text, StandardCharsets.UTF_8);
            Files.writeString(htmlPath, html, StandardCharsets.UTF_8);
        } catch (IOException e) {
            throw new UncheckedIOException("Dev çıkış kutusuna yazılamadı: " + folder, e);
        }
        System.out.println("[nafru] dev: e-posta gönderilmedi\n  " + txtPath + "\n  " + htmlPath + "\n\n" + text);
        return new IdResponse(id);
    }
}
