package com.nafru.email;

import java.time.Duration;

/**
 * API anahtarıyla Nafru Email istemcisi (Resend SDK'sıyla aynı biçim). Hatalar {@link NafruException} olarak fırlatılır. İş parçacığı
 * güvenlidir.
 *
 * <pre>{@code
 * NafruEmail nafru = new NafruEmail("nafru_...");   // ya da new NafruEmail(): NAFRU_API_KEY ortam değişkeninden
 * nafru.emails().send(new SendEmailInput().from("a@ornek.com").to("b@ornek.com").subject("Merhaba").text("…"));
 * NafruEmail local = NafruEmail.builder().apiKey("nafru_...").baseUrl("http://localhost:48787/api").build();
 * }</pre>
 */
public final class NafruEmail {
    public static final String SDK_VERSION = "0.1.1";
    /** Nafru Email üretim API'si; {@code baseUrl} verilmezse kullanılır. */
    public static final String DEFAULT_BASE_URL = "https://email.nafru.com/api";
    /** Ortam okuma; testler değiştirir. */
    static java.util.function.UnaryOperator<String> env = System::getenv;
    static final String USER_AGENT = "nafru-email-java/" + SDK_VERSION;

    private final Emails emails;
    private final Domains domains;
    private final Contacts contacts;
    private final ContactProperties contactProperties;
    private final Segments segments;
    private final Topics topics;
    private final Broadcasts broadcasts;
    private final Templates templates;
    private final BrandResource brand;
    private final Webhooks webhooks;
    private final ApiKeys apiKeys;
    private final Events events;

    /** {@code apiKey} boşsa {@code NAFRU_API_KEY} ortam değişkeni okunur. */
    public NafruEmail(String apiKey) {
        this(builder().apiKey(apiKey));
    }

    /** API anahtarı {@code NAFRU_API_KEY} ortam değişkeninden. */
    public NafruEmail() {
        this(builder());
    }

    private NafruEmail(Builder builder) {
        String apiKey = builder.apiKey == null || builder.apiKey.isEmpty() ? env.apply("NAFRU_API_KEY") : builder.apiKey;
        if (apiKey == null || apiKey.isEmpty()) throw new IllegalArgumentException("Nafru SDK: apiKey gerekli");
        Http.Caller http = new Http(effectiveBaseUrl(builder.baseUrl), builder.transport, builder.maxRetries, builder.timeout, USER_AGENT)
                .caller(apiKey);
        this.emails = new Emails(http, DevOutbox.resolve(builder.devOutboxSet, builder.devOutbox, env.apply("NODE_ENV")));
        this.domains = new Domains(http);
        this.contacts = new Contacts(http);
        this.contactProperties = new ContactProperties(http);
        this.segments = new Segments(http);
        this.topics = new Topics(http);
        this.broadcasts = new Broadcasts(http);
        this.templates = new Templates(http);
        this.brand = new BrandResource(http);
        this.webhooks = new Webhooks(http);
        this.apiKeys = new ApiKeys(http);
        this.events = new Events(http);
    }

    public static Builder builder() { return new Builder(); }

    static String effectiveBaseUrl(String baseUrl) {
        return Http.requireSecureUrl(baseUrl == null || baseUrl.isEmpty() ? DEFAULT_BASE_URL : baseUrl, "baseUrl");
    }

    public Emails emails() { return emails; }
    public Domains domains() { return domains; }
    public Contacts contacts() { return contacts; }
    public ContactProperties contactProperties() { return contactProperties; }
    public Segments segments() { return segments; }
    public Topics topics() { return topics; }
    public Broadcasts broadcasts() { return broadcasts; }
    public Templates templates() { return templates; }
    /** Çalışma alanı markası (logo, renkler, yazı tipi, altbilgi). */
    public BrandResource brand() { return brand; }
    public Webhooks webhooks() { return webhooks; }
    public ApiKeys apiKeys() { return apiKeys; }
    public Events events() { return events; }

    /** API anahtarı yazılmaz. */
    @Override
    public String toString() { return "NafruEmail[apiKey=" + Redact.SECRET + "]"; }

    public static final class Builder {
        private String apiKey;
        private String baseUrl;
        private Transport transport = new HttpClientTransport();
        private int maxRetries = 2;
        private Duration timeout = Duration.ofSeconds(30);
        private String devOutbox;
        private boolean devOutboxSet;

        private Builder() {}

        /** Dashboard'dan üretilen API anahtarı; verilmezse {@code NAFRU_API_KEY}. İstemciye gömmeyin; {@code sending_access} anahtarı bile e-posta gönderebilir. */
        public Builder apiKey(String apiKey) { this.apiKey = apiKey; return this; }

        /** API'nin kök adresi; varsayılan {@link #DEFAULT_BASE_URL} (yerelde {@code http://localhost:48787/api}). */
        public Builder baseUrl(String baseUrl) { this.baseUrl = baseUrl; return this; }

        /** Özel taşıyıcı (test, proxy, kendi HTTP istemciniz). */
        public Builder transport(Transport transport) { this.transport = transport; return this; }

        /** {@code 429} ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme sayısı; varsayılan 2, {@code 0} kapatır. */
        public Builder maxRetries(int maxRetries) { this.maxRetries = maxRetries; return this; }

        /** İstek başına zaman aşımı; varsayılan 30 sn. */
        public Builder timeout(Duration timeout) { this.timeout = timeout; return this; }

        /**
         * Dev çıkış kutusu: {@code emails().send}/{@code batch} gönderim yapmaz, e-postayı bu klasöre {@code .txt} + {@code .html}
         * yazar. Çağrılmazsa {@code NODE_ENV=development} iken {@code .nafru/emails}, aksi hâlde kapalı.
         */
        public Builder devOutbox(String dir) { this.devOutbox = dir; this.devOutboxSet = true; return this; }

        /** {@code false}: ortam ne olursa olsun gerçek gönderim. */
        public Builder devOutbox(boolean enabled) {
            return enabled ? devOutbox(DevOutbox.DEFAULT_DIR) : devOutbox((String) null);
        }

        public NafruEmail build() { return new NafruEmail(this); }
    }
}
