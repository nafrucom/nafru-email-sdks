package nafruemail

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"net/http"
	"net/url"
	"strings"
	"sync"
	"time"
)

type appCredentials struct {
	clientID     string
	clientSecret string
}

// createPKCE, PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması.
func createPKCE() (verifier, challenge string, err error) {
	raw := make([]byte, 32)
	if _, err := rand.Read(raw); err != nil {
		return "", "", err
	}
	verifier = base64.RawURLEncoding.EncodeToString(raw)
	digest := sha256.Sum256([]byte(verifier))
	return verifier, base64.RawURLEncoding.EncodeToString(digest[:]), nil
}

// AuthorizeURL müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresidir. CodeVerifier'ı oturumda saklayın; dönüşte
// Exchange'e verin. Dönüşte state'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
func (c *Connect) AuthorizeURL(input AuthorizeURLInput) (*AuthorizeURL, error) {
	if input.State == "" {
		return nil, errors.New("Nafru SDK: state gerekli (CSRF koruması)")
	}
	if len(input.Scopes) == 0 {
		return nil, errors.New("Nafru SDK: en az bir izin (scopes) gerekli")
	}
	verifier, challenge, err := createPKCE()
	if err != nil {
		return nil, err
	}
	query := url.Values{}
	query.Set("client_id", c.creds.clientID)
	query.Set("redirect_uri", input.RedirectURI)
	query.Set("state", input.State)
	query.Set("scope", strings.Join(input.Scopes, " "))
	query.Set("code_challenge", challenge)
	query.Set("code_challenge_method", "S256")
	if input.LoginHint != "" {
		query.Set("login_hint", input.LoginHint)
	}
	return &AuthorizeURL{
		URL:          strings.TrimRight(c.webURL, "/") + "/connect?" + query.Encode(),
		CodeVerifier: verifier,
	}, nil
}

type grantPayload struct {
	AccessToken  string   `json:"access_token"`
	RefreshToken string   `json:"refresh_token"`
	ExpiresIn    int64    `json:"expires_in"`
	ConnectionID string   `json:"connection_id"`
	Scopes       []string `json:"scopes"`
}

// Exchange, dönüşteki tek kullanımlık kodu bağlantıya çevirir (sunucunuzdan çağırın).
func (c *Connect) Exchange(ctx context.Context, input ExchangeInput) (*ConnectionGrant, error) {
	payload, err := call[grantPayload](ctx, c.shared.do, requestInput{method: http.MethodPost, path: "/oauth/token", body: map[string]string{
		"grant_type":    "authorization_code",
		"client_id":     c.creds.clientID,
		"client_secret": c.creds.clientSecret,
		"code":          input.Code,
		"code_verifier": input.CodeVerifier,
		"redirect_uri":  input.RedirectURI,
	}})
	if err != nil {
		return nil, err
	}
	return &ConnectionGrant{ConnectionID: payload.ConnectionID, RefreshToken: payload.RefreshToken, Scopes: payload.Scopes}, nil
}

// Revoke, bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur.
func (c *Connect) Revoke(ctx context.Context, refreshToken string) error {
	return c.shared.do(ctx, requestInput{method: http.MethodPost, path: "/oauth/revoke", body: map[string]string{
		"client_id":     c.creds.clientID,
		"client_secret": c.creds.clientSecret,
		"token":         refreshToken,
	}}, nil)
}

// ---- Belirteç yönetimi ----

// earlyRefresh: süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı).
const earlyRefresh = 30 * time.Second

type refreshCall struct {
	done  chan struct{}
	token string
	err   error
}

// tokenManager, bağlantının erişim belirtecini tutar ve yeniler. Eşzamanlı çağrılar TEK yenilemeyi paylaşır (tek uçuş):
// dönüşlü yenileme belirteci ikinci bir eşzamanlı yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
type tokenManager struct {
	oauth     caller
	creds     appCredentials
	onRefresh func(ctx context.Context, tokens ConnectionTokens) error

	mu           sync.Mutex
	refreshToken string
	accessToken  string
	expiresAt    time.Time
	inflight     *refreshCall
	// unpersisted: yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı; eski belirteç artık geçersiz.
	unpersisted bool
}

func (m *tokenManager) persist(ctx context.Context, refreshToken string) error {
	err := m.onRefresh(ctx, ConnectionTokens{RefreshToken: refreshToken})
	m.mu.Lock()
	m.unpersisted = err != nil
	m.mu.Unlock()
	if err != nil {
		return &Error{Name: "token_persist_failed", Message: "Yeni yenileme belirteci saklanamadı: " + err.Error()}
	}
	return nil
}

func isRevoked(err *Error) bool {
	return err.Name == "invalid_grant" || err.Name == "connection_revoked" ||
		(err.StatusCode == http.StatusForbidden && err.Name != "rate_limit_exceeded")
}

func (m *tokenManager) doRefresh(ctx context.Context, c *refreshCall, refreshToken string) {
	defer func() {
		m.mu.Lock()
		m.inflight = nil
		m.mu.Unlock()
		close(c.done)
	}()
	payload, err := call[grantPayload](ctx, m.oauth, requestInput{method: http.MethodPost, path: "/oauth/token", body: map[string]string{
		"grant_type":    "refresh_token",
		"client_id":     m.creds.clientID,
		"client_secret": m.creds.clientSecret,
		"refresh_token": refreshToken,
	}})
	if err != nil {
		// Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi döner.
		var apiErr *Error
		if errors.As(err, &apiErr) && isRevoked(apiErr) {
			revoked := *apiErr
			revoked.Name = "connection_revoked"
			revoked.Message = "Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir."
			err = &revoked
		}
		c.err = err
		return
	}
	m.mu.Lock()
	m.refreshToken = payload.RefreshToken
	m.accessToken = payload.AccessToken
	m.expiresAt = time.Now().Add(time.Duration(payload.ExpiresIn) * time.Second)
	m.mu.Unlock()
	if err := m.persist(ctx, payload.RefreshToken); err != nil {
		c.err = err
		return
	}
	c.token = payload.AccessToken
}

// refreshLocked tek uçuşu başlatır ya da süren yenilemeye katılır; m.mu tutulurken çağrılır.
func (m *tokenManager) refreshLocked(ctx context.Context) *refreshCall {
	if m.inflight == nil {
		m.inflight = &refreshCall{done: make(chan struct{})}
		// İlk çağıranın iptali paylaşılan yenilemeyi bozmasın.
		go m.doRefresh(context.WithoutCancel(ctx), m.inflight, m.refreshToken)
	}
	return m.inflight
}

func wait(ctx context.Context, c *refreshCall) (string, error) {
	select {
	case <-c.done:
		return c.token, c.err
	case <-ctx.Done():
		return "", networkError("İstek iptal edildi")
	}
}

// token geçerli erişim belirtecini verir; yoksa ya da dolmak üzereyse tek uçuşla yeniler.
func (m *tokenManager) token(ctx context.Context) (string, error) {
	m.mu.Lock()
	if m.unpersisted {
		refreshToken := m.refreshToken
		m.mu.Unlock()
		if err := m.persist(ctx, refreshToken); err != nil {
			return "", err
		}
		m.mu.Lock()
	}
	if m.accessToken != "" && time.Now().Before(m.expiresAt.Add(-earlyRefresh)) {
		token := m.accessToken
		m.mu.Unlock()
		return token, nil
	}
	c := m.refreshLocked(ctx)
	m.mu.Unlock()
	return wait(ctx, c)
}

// invalidate: sunucu 401 invalid_token dedi; eldeki belirteci at ve yenile (aynı belirteçle eşzamanlı 401'ler tek yenilemeyi paylaşır).
func (m *tokenManager) invalidate(ctx context.Context, stale string) (string, error) {
	m.mu.Lock()
	if m.accessToken == stale {
		m.accessToken = ""
	}
	if m.accessToken != "" {
		token := m.accessToken
		m.mu.Unlock()
		return token, nil
	}
	c := m.refreshLocked(ctx)
	m.mu.Unlock()
	return wait(ctx, c)
}

// ---- Bağlantı ----

// ConnectionOptions: OnTokenRefresh yeni yenileme belirteci döndüğünde çağrılır; yeni değeri KALICI olarak yazmadan eskisi
// geçersizdir. Hata dönerse çağrı token_persist_failed ile döner ve sonraki çağrıda saklama yeniden denenir.
type ConnectionOptions struct {
	RefreshToken   string
	OnTokenRefresh func(ctx context.Context, tokens ConnectionTokens) error
}

// Connection, bir müşteri bağlantısı adına çağrı yapar. Yönetim uçları (anahtar, domain, kişi, kampanya) yoktur.
type Connection struct {
	ID        string
	Senders   *ConnectionSendersResource
	Templates *ConnectionTemplatesResource
	Emails    *ConnectionEmails
	call      caller
}

// Connection, saklanan yenileme belirteciyle bir müşteri bağlantısı açar. Yenileme otomatiktir; yeni belirteç
// OnTokenRefresh ile gelir. Aynı bağlantı için tek bir *Connection paylaşın: tek uçuş örnek başınadır.
func (a *Connect) Connection(connectionID string, options ConnectionOptions) *Connection {
	tokens := &tokenManager{
		oauth:        a.shared.do,
		creds:        a.creds,
		onRefresh:    options.OnTokenRefresh,
		refreshToken: options.RefreshToken,
	}
	if tokens.onRefresh == nil {
		tokens.onRefresh = func(context.Context, ConnectionTokens) error { return nil }
	}
	base := a.shared
	// Her çağrı kendi belirtecini izler: 401 invalid_token ise o belirteç geçersiz kılınır ve bir kez yeniden denenir.
	c := func(ctx context.Context, in requestInput, out any) error {
		var current string
		h := *base
		h.authorize = func(ctx context.Context) (string, error) {
			token, err := tokens.token(ctx)
			if err == nil {
				current = token
			}
			return token, err
		}
		err := h.do(ctx, in, out)
		var apiErr *Error
		if !errors.As(err, &apiErr) || apiErr.Name != "invalid_token" || current == "" {
			return err
		}
		if _, err := tokens.invalidate(ctx, current); err != nil {
			return err
		}
		return h.do(ctx, in, out)
	}
	emails := &EmailsResource{call: c, devOutbox: a.devOutbox}
	return &Connection{
		ID:        connectionID,
		Senders:   &ConnectionSendersResource{call: c},
		Templates: &ConnectionTemplatesResource{call: c},
		Emails:    &ConnectionEmails{emails: emails},
		call:      c,
	}
}

// Status: GET /connection; hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.
func (c *Connection) Status(ctx context.Context) (*ConnectionStatus, error) {
	return get[ConnectionStatus](ctx, c.call, "/connection", nil)
}

type ConnectionSendersResource struct{ call caller }

func (r *ConnectionSendersResource) List(ctx context.Context) (*ConnectionSenders, error) {
	return get[ConnectionSenders](ctx, r.call, "/senders", nil)
}

type ConnectionTemplatesResource struct{ call caller }

// List müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kopyası paketi gölgeler).
func (r *ConnectionTemplatesResource) List(ctx context.Context) (*ListResponse[ConnectionTemplate], error) {
	return get[ListResponse[ConnectionTemplate]](ctx, r.call, "/templates", nil)
}

// ConnectionEmails, bağlantı adına yalnız gönderim ve okuma sunar.
type ConnectionEmails struct{ emails *EmailsResource }

func (e *ConnectionEmails) Send(ctx context.Context, input *SendEmailInput, options ...SendEmailOptions) (*SendEmailResponse, error) {
	return e.emails.Send(ctx, input, options...)
}

func (e *ConnectionEmails) Get(ctx context.Context, id string) (*Email, error) {
	return e.emails.Get(ctx, id)
}

func (e *ConnectionEmails) List(ctx context.Context, query *ListEmailsQuery) (*ListResponse[EmailListItem], error) {
	return e.emails.List(ctx, query)
}
