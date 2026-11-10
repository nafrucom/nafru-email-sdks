package com.nafru.email;

import static org.junit.jupiter.api.Assertions.*;

import com.nafru.email.model.BatchEmailItem;
import com.nafru.email.model.IdResponse;
import com.nafru.email.model.SendEmailInput;
import java.io.ByteArrayOutputStream;
import java.io.PrintStream;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.util.List;
import java.util.stream.Stream;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

class DevOutboxTest {
    @Test
    void writesFilesInsteadOfSending(@TempDir Path dir) throws Exception {
        MockTransport mock = new MockTransport(request -> { throw new AssertionError("taşıyıcı çağrılmamalı"); });
        NafruEmail nafru = NafruEmail.builder().apiKey("k").baseUrl("http://api.localhost").transport(mock).devOutbox(dir.toString()).build();
        PrintStream original = System.out;
        ByteArrayOutputStream log = new ByteArrayOutputStream();
        System.setOut(new PrintStream(log, true, StandardCharsets.UTF_8));
        IdResponse sent;
        try {
            sent = nafru.emails().send(new SendEmailInput().from("a@x.com").to("b@y.com", "c@y.com").subject("Merhaba")
                    .html("<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>"));
            assertEquals(1, nafru.emails().batch(List.of(new BatchEmailItem().from("a@x.com").to("d@y.com").subject("S").text("düz")))
                    .data().size());
        } finally {
            System.setOut(original);
        }
        assertTrue(sent.id().startsWith("dev_"));
        List<Path> files;
        try (Stream<Path> stream = Files.list(dir)) { files = stream.sorted().toList(); }
        assertEquals(2, files.stream().filter(f -> f.toString().endsWith(".txt")).count());
        assertEquals(2, files.stream().filter(f -> f.toString().endsWith(".html")).count());
        Path txt = files.stream().filter(f -> f.toString().contains(sent.id()) && f.toString().endsWith(".txt")).findFirst().orElseThrow();
        String text = Files.readString(txt);
        assertTrue(text.contains("To: b@y.com, c@y.com"));
        assertTrue(text.contains("Subject: Merhaba"));
        assertTrue(text.contains("Selam Ali\n& hoş geldin"));
        assertTrue(Files.readString(Path.of(txt.toString().replace(".txt", ".html"))).contains("<b>Ali</b>"));
        assertTrue(log.toString(StandardCharsets.UTF_8).contains(txt.toString()));
        assertTrue(mock.calls.isEmpty());
    }

    @Test
    void defaultOnlyInDevelopment() {
        assertEquals(".nafru/emails", DevOutbox.resolve(false, null, "development"));
        assertNull(DevOutbox.resolve(true, null, "development"));
        assertNull(DevOutbox.resolve(false, null, "production"));
        assertNull(DevOutbox.resolve(false, null, null));
        assertEquals("tmp/mail", DevOutbox.resolve(true, "tmp/mail", null));
    }
}
