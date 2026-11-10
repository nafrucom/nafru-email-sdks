// Package nafruemail, Nafru Email için resmi Go SDK'sıdır: Resend uyumlu gönderim API'si, kişiler, kampanyalar, olaylar,
// webhook doğrulama ve "Nafru ile bağlan" (OAuth). Yalnız standart kitaplık kullanır.
package nafruemail

import (
	"context"
	"errors"
	"net/http"
	"os"
	"regexp"
	"sync"
	"time"
)

// Version, SDK sürümüdür (User-Agent: nafru-email-go/<Version>).
const Version = "0.1.1"

// DefaultBaseURL, Nafru Email üretim API'sidir; BaseURL verilmezse kullanılır.
const DefaultBaseURL = "https://email.nafru.com/api"

func baseURLOrDefault(baseURL string) string {
	if baseURL == "" {
		return DefaultBaseURL
	}
	return baseURL
}

const (
	defaultMaxRetries = 2
	defaultTimeout    = 30 * time.Second
)

type clientConfig struct {
	baseURL          string
	httpClient       *http.Client
	maxRetries       *int
	timeout          time.Duration
	devOutbox        string
	disableDevOutbox bool
}

// Option, NewClient'ın isteğe bağlı ayarıdır.
type Option func(*clientConfig)

// WithBaseURL API'nin kök adresini değiştirir; varsayılan DefaultBaseURL (yerelde http://localhost:48787/api).
func WithBaseURL(baseURL string) Option { return func(c *clientConfig) { c.baseURL = baseURL } }

// WithHTTPClient özel istemci verir (test, proxy); varsayılan http.DefaultClient.
func WithHTTPClient(client *http.Client) Option {
	return func(c *clientConfig) { c.httpClient = client }
}

// WithMaxRetries 429 ve güvenli isteklerde yeniden deneme sayısıdır; varsayılan 2, 0 kapatır.
func WithMaxRetries(n int) Option { return func(c *clientConfig) { c.maxRetries = &n } }

// WithTimeout deneme başına zaman aşımıdır; varsayılan 30 sn.
func WithTimeout(timeout time.Duration) Option { return func(c *clientConfig) { c.timeout = timeout } }

// WithDevOutbox: Emails.Send/Batch göndermez, e-postayı bu klasöre .txt + .html yazar.
// Verilmezse NODE_ENV=development iken .nafru/emails, aksi hâlde kapalı.
func WithDevOutbox(dir string) Option { return func(c *clientConfig) { c.devOutbox = dir } }

// WithoutDevOutbox her zaman gerçek gönderim yapar (NODE_ENV=development olsa bile).
func WithoutDevOutbox() Option { return func(c *clientConfig) { c.disableDevOutbox = true } }

// Client, API anahtarlı Nafru istemcisidir.
type Client struct {
	Emails            *EmailsResource
	Domains           *DomainsResource
	Contacts          *ContactsResource
	ContactProperties *ContactPropertiesResource
	Segments          *SegmentsResource
	Topics            *TopicsResource
	Broadcasts        *BroadcastsResource
	Templates         *TemplatesResource
	Brand             *BrandResource
	Webhooks          *WebhooksResource
	APIKeys           *APIKeysResource
	Events            *EventsResource
}

func newHTTP(baseURL string, client *http.Client, maxRetries *int, timeout time.Duration) *httpClient {
	if client == nil {
		client = http.DefaultClient
	}
	h := &httpClient{
		baseURL:     baseURL,
		client:      noRedirects(client),
		maxRetries:  defaultMaxRetries,
		timeout:     timeout,
		userAgent:   "nafru-email-go/" + Version,
		authorize:   func(context.Context) (string, error) { return "", nil },
		deprecation: &sync.Once{},
	}
	if maxRetries != nil {
		h.maxRetries = *maxRetries
	}
	if h.timeout <= 0 {
		h.timeout = defaultTimeout
	}
	return h
}

// NewClient, API anahtarlı istemciyi kurar (resend.NewClient gibi). apiKey boşsa NAFRU_API_KEY ortam değişkeni okunur;
// o da boşsa hata döner. Anahtarı tarayıcıya/istemci uygulamasına gömmeyin.
//
//	client, err := nafru.NewClient("nafru_...")
//	client, err := nafru.NewClient("", nafru.WithBaseURL("http://localhost:48787/api"))
func NewClient(apiKey string, options ...Option) (*Client, error) {
	if apiKey == "" {
		apiKey = os.Getenv("NAFRU_API_KEY")
	}
	if apiKey == "" {
		return nil, errors.New("Nafru SDK: apiKey gerekli")
	}
	var config clientConfig
	for _, option := range options {
		option(&config)
	}
	baseURL := baseURLOrDefault(config.baseURL)
	if err := validateBaseURL(baseURL, "baseUrl"); err != nil {
		return nil, err
	}
	h := newHTTP(baseURL, config.httpClient, config.maxRetries, config.timeout)
	h.authorize = func(context.Context) (string, error) { return apiKey, nil }
	c := caller(h.do)
	return &Client{
		Emails:  &EmailsResource{call: c, devOutbox: resolveDevOutbox(config.devOutbox, config.disableDevOutbox)},
		Domains: &DomainsResource{call: c},
		Contacts: &ContactsResource{
			call:     c,
			Segments: &ContactSegmentsResource{call: c},
			Topics:   &ContactTopicsResource{call: c},
		},
		ContactProperties: &ContactPropertiesResource{call: c},
		Segments:          &SegmentsResource{call: c},
		Topics:            &TopicsResource{call: c},
		Broadcasts:        &BroadcastsResource{call: c},
		Templates:         &TemplatesResource{call: c},
		Brand:             &BrandResource{call: c},
		Webhooks:          &WebhooksResource{call: c},
		APIKeys:           &APIKeysResource{call: c},
		Events:            &EventsResource{call: c},
	}, nil
}

// ConnectOptions, "Nafru ile bağlan" istemcisinin ayarlarıdır.
type ConnectOptions struct {
	// ClientID kayıtlı uygulamanın app_… kimliği.
	ClientID string
	// ClientSecret yalnız sunucunuzda kalır.
	ClientSecret string
	// BaseURL API'nin kök adresi; boşsa DefaultBaseURL.
	BaseURL string
	// WebURL izin ekranının kök adresi; boşsa BaseURL sonundaki /api atılır.
	WebURL     string
	HTTPClient *http.Client
	// MaxRetries nil ise 2, nafru.Ptr(0) kapatır.
	MaxRetries *int
	Timeout    time.Duration
	// DevOutbox verilirse Connection(...).Emails.Send göndermez, bu klasöre yazar (bkz. WithDevOutbox).
	DevOutbox        string
	DisableDevOutbox bool
}

// Connect, "Nafru ile bağlan" istemcisidir (OAuth): müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına
// gönderir. İzin adresi (AuthorizeURL), kod değişimi (Exchange), iptal (Revoke) ve bağlantı (Connection) buradadır.
// Tek alan adı/anahtar için NewClient kullanın.
type Connect struct {
	shared    *httpClient
	creds     appCredentials
	webURL    string
	devOutbox string
}

var trailingAPI = regexp.MustCompile(`/api/*$`)

// NewConnect, "Nafru ile bağlan" istemcisini kurar. ClientID ve ClientSecret zorunludur.
func NewConnect(options ConnectOptions) (*Connect, error) {
	if options.ClientID == "" {
		return nil, errors.New("Nafru SDK: clientId gerekli")
	}
	if options.ClientSecret == "" {
		return nil, errors.New("Nafru SDK: clientSecret gerekli")
	}
	baseURL := baseURLOrDefault(options.BaseURL)
	if err := validateBaseURL(baseURL, "baseUrl"); err != nil {
		return nil, err
	}
	// Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok (varsayılan authorize "" döner).
	shared := newHTTP(baseURL, options.HTTPClient, options.MaxRetries, options.Timeout)
	webURL := options.WebURL
	if webURL == "" {
		webURL = trailingAPI.ReplaceAllString(baseURL, "")
	}
	if err := validateBaseURL(webURL, "webUrl"); err != nil {
		return nil, err
	}
	creds := appCredentials{clientID: options.ClientID, clientSecret: options.ClientSecret}
	return &Connect{
		shared:    shared,
		webURL:    webURL,
		creds:     creds,
		devOutbox: resolveDevOutbox(options.DevOutbox, options.DisableDevOutbox),
	}, nil
}
