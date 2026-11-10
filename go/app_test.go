package nafruemail

import (
	"context"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"fmt"
	"net/http"
	"net/url"
	"reflect"
	"regexp"
	"strings"
	"sync"
	"sync/atomic"
	"testing"
	"time"
)

var urlSafe43 = regexp.MustCompile(`^[A-Za-z0-9_-]{43}$`)

func newTestApp(t *testing.T, route func(recorded) (*http.Response, error)) (*Connect, *mockServer) {
	t.Helper()
	server := &mockServer{}
	app, err := NewConnect(ConnectOptions{
		ClientID: "app_x", ClientSecret: "nfs_secret", BaseURL: "https://api.test/", WebURL: "https://web.test",
		HTTPClient: server.client(route), MaxRetries: Ptr(0), DisableDevOutbox: true,
	})
	if err != nil {
		t.Fatal(err)
	}
	return app, server
}

func tokenBody(n int) string {
	return fmt.Sprintf(`{"access_token":"nfa_%d","refresh_token":"nfr_%d","token_type":"Bearer","expires_in":3600,"connection_id":"conn_1","scopes":["emails.send"]}`, n, n)
}

func isToken(call recorded) bool { return strings.HasSuffix(call.url, "/oauth/token") }

func apiCalls(calls []recorded) []recorded {
	var out []recorded
	for _, call := range calls {
		if !strings.Contains(call.url, "/oauth/") {
			out = append(out, call)
		}
	}
	return out
}

func countToken(calls []recorded) int {
	n := 0
	for _, call := range calls {
		if isToken(call) {
			n++
		}
	}
	return n
}

func TestPKCE(t *testing.T) {
	verifier, challenge, err := createPKCE()
	if err != nil || !urlSafe43.MatchString(verifier) {
		t.Fatalf("doğrulayıcı %q", verifier)
	}
	digest := sha256.Sum256([]byte(verifier))
	if challenge != base64.RawURLEncoding.EncodeToString(digest[:]) {
		t.Fatal("sınama SHA-256 base64url değil")
	}
	if again, _, _ := createPKCE(); again == verifier {
		t.Fatal("doğrulayıcı rastgele değil")
	}
}

func TestAuthorizeURL(t *testing.T) {
	app, _ := newTestApp(t, func(recorded) (*http.Response, error) { return respond(200, `{}`), nil })
	result, err := app.AuthorizeURL(AuthorizeURLInput{RedirectURI: "https://scout.test/cb", State: "st1",
		Scopes: []string{ScopeEmailsSend, ScopeTemplatesRead}, LoginHint: "a@b.co"})
	if err != nil {
		t.Fatal(err)
	}
	parsed, _ := url.Parse(result.URL)
	if parsed.Scheme+"://"+parsed.Host+parsed.Path != "https://web.test/connect" {
		t.Fatalf("adres %s", result.URL)
	}
	q := parsed.Query()
	want := map[string]string{"client_id": "app_x", "redirect_uri": "https://scout.test/cb", "state": "st1",
		"scope": "emails.send templates.read", "code_challenge_method": "S256", "login_hint": "a@b.co"}
	for key, value := range want {
		if q.Get(key) != value {
			t.Errorf("%s = %q", key, q.Get(key))
		}
	}
	if !urlSafe43.MatchString(q.Get("code_challenge")) || !urlSafe43.MatchString(result.CodeVerifier) {
		t.Fatal("PKCE değerleri biçimsiz")
	}
	if _, err := app.AuthorizeURL(AuthorizeURLInput{RedirectURI: "x", Scopes: []string{ScopeEmailsSend}}); err == nil {
		t.Fatal("state zorunlu olmalı")
	}
	if _, err := app.AuthorizeURL(AuthorizeURLInput{RedirectURI: "x", State: "s"}); err == nil {
		t.Fatal("scopes zorunlu olmalı")
	}
}

func TestWebURLDefaultsToBaseWithoutAPI(t *testing.T) {
	app, err := NewConnect(ConnectOptions{ClientID: "a", ClientSecret: "s", BaseURL: "https://email.nafru.example/api/"})
	if err != nil || app.webURL != "https://email.nafru.example" {
		t.Fatalf("webURL %q, %v", app.webURL, err)
	}
	app, err = NewConnect(ConnectOptions{ClientID: "a", ClientSecret: "s"})
	if err != nil || app.shared.baseURL != DefaultBaseURL || app.webURL != "https://email.nafru.com" {
		t.Fatalf("varsayılan baseURL %q webURL %q, %v", app.shared.baseURL, app.webURL, err)
	}
}

func TestExchangeAndRevoke(t *testing.T) {
	app, server := newTestApp(t, func(recorded) (*http.Response, error) { return respond(200, tokenBody(1)), nil })
	grant, err := app.Exchange(ctx, ExchangeInput{Code: "nfc_1", CodeVerifier: strings.Repeat("v", 43), RedirectURI: "https://scout.test/cb"})
	if err != nil || !reflect.DeepEqual(grant, &ConnectionGrant{ConnectionID: "conn_1", RefreshToken: "nfr_1", Scopes: []string{"emails.send"}}) {
		t.Fatalf("grant %+v, %v", grant, err)
	}
	call := server.snapshot()[0]
	body := call.json(t).(map[string]any)
	if call.url != "https://api.test/oauth/token" || call.header.Get("Authorization") != "" ||
		body["grant_type"] != "authorization_code" || body["client_secret"] != "nfs_secret" || body["code"] != "nfc_1" {
		t.Fatalf("istek %+v", call)
	}

	if err := app.Revoke(ctx, "nfr_1"); err != nil {
		t.Fatal(err)
	}
	want := map[string]any{"client_id": "app_x", "client_secret": "nfs_secret", "token": "nfr_1"}
	if got := server.snapshot()[1].json(t); !reflect.DeepEqual(got, want) {
		t.Fatalf("revoke gövdesi %v", got)
	}
}

func TestExchangeError(t *testing.T) {
	app, _ := newTestApp(t, func(recorded) (*http.Response, error) {
		return respond(400, `{"statusCode":400,"name":"invalid_grant","message":"invalid"}`), nil
	})
	_, err := app.Exchange(ctx, ExchangeInput{Code: "c", CodeVerifier: "v", RedirectURI: "r"})
	if got := apiError(t, err); got.StatusCode != 400 || got.Name != "invalid_grant" {
		t.Fatalf("hata %+v", got)
	}
}

func openConnection(t *testing.T, route func(recorded) (*http.Response, error)) (*Connection, *mockServer, *[]string) {
	app, server := newTestApp(t, route)
	var mu sync.Mutex
	saved := []string{}
	connection := app.Connection("conn_1", ConnectionOptions{
		RefreshToken: "nfr_0",
		OnTokenRefresh: func(_ context.Context, tokens ConnectionTokens) error {
			mu.Lock()
			saved = append(saved, tokens.RefreshToken)
			mu.Unlock()
			return nil
		},
	})
	return connection, server, &saved
}

func TestConnectionFirstCallRefreshes(t *testing.T) {
	connection, server, saved := openConnection(t, func(call recorded) (*http.Response, error) {
		if isToken(call) {
			return respond(200, tokenBody(1)), nil
		}
		return respond(200, `{"object":"connection","id":"conn_1","ready":true}`), nil
	})
	status, err := connection.Status(ctx)
	if err != nil || !status.Ready {
		t.Fatalf("durum %+v, %v", status, err)
	}
	calls := server.snapshot()
	if !reflect.DeepEqual(*saved, []string{"nfr_1"}) {
		t.Fatalf("saklanan %v", *saved)
	}
	body := calls[0].json(t).(map[string]any)
	if body["grant_type"] != "refresh_token" || body["refresh_token"] != "nfr_0" {
		t.Fatalf("yenileme gövdesi %v", body)
	}
	first := apiCalls(calls)[0]
	if first.url != "https://api.test/connection" || first.header.Get("Authorization") != "Bearer nfa_1" {
		t.Fatalf("api çağrısı %+v", first)
	}
}

func TestConnectionSingleFlightRefresh(t *testing.T) {
	connection, server, saved := openConnection(t, func(call recorded) (*http.Response, error) {
		if isToken(call) {
			time.Sleep(20 * time.Millisecond)
			return respond(200, tokenBody(1)), nil
		}
		return respond(200, `{"ready":true}`), nil
	})
	var wg sync.WaitGroup
	errs := make([]error, 5)
	for i := range errs {
		wg.Add(1)
		go func(i int) {
			defer wg.Done()
			_, errs[i] = connection.Status(ctx)
		}(i)
	}
	wg.Wait()
	for _, err := range errs {
		if err != nil {
			t.Fatal(err)
		}
	}
	if n := countToken(server.snapshot()); n != 1 {
		t.Fatalf("yenileme sayısı %d", n)
	}
	if !reflect.DeepEqual(*saved, []string{"nfr_1"}) {
		t.Fatalf("saklanan %v", *saved)
	}
	if _, err := connection.Status(ctx); err != nil || countToken(server.snapshot()) != 1 {
		t.Fatal("belirteç yeniden kullanılmadı")
	}
}

func TestConnectionInvalidTokenRetriesOnce(t *testing.T) {
	var refreshes atomic.Int32
	connection, server, saved := openConnection(t, func(call recorded) (*http.Response, error) {
		if isToken(call) {
			return respond(200, tokenBody(int(refreshes.Add(1)))), nil
		}
		if call.header.Get("Authorization") == "Bearer nfa_1" {
			return respond(401, `{"statusCode":401,"name":"invalid_token","message":"expired"}`), nil
		}
		return respond(200, `{"ready":true}`), nil
	})
	if _, err := connection.Status(ctx); err != nil {
		t.Fatal(err)
	}
	var auths []string
	for _, call := range apiCalls(server.snapshot()) {
		auths = append(auths, call.header.Get("Authorization"))
	}
	if refreshes.Load() != 2 || !reflect.DeepEqual(auths, []string{"Bearer nfa_1", "Bearer nfa_2"}) {
		t.Fatalf("yenileme %d, auth %v", refreshes.Load(), auths)
	}
	if !reflect.DeepEqual(*saved, []string{"nfr_1", "nfr_2"}) {
		t.Fatalf("dönüşlü belirteç saklanmadı: %v", *saved)
	}
}

func TestConnectionRevoked(t *testing.T) {
	connection, server, _ := openConnection(t, func(recorded) (*http.Response, error) {
		return respond(400, `{"statusCode":400,"name":"invalid_grant","message":"invalid"}`), nil
	})
	_, err := connection.Status(ctx)
	if got := apiError(t, err); got.Name != "connection_revoked" {
		t.Fatalf("hata %+v", got)
	}
	if len(apiCalls(server.snapshot())) != 0 {
		t.Fatal("api çağrısı yapılmamalıydı")
	}
}

func TestConnectionPersistFailureRetriedNextCall(t *testing.T) {
	app, server := newTestApp(t, func(recorded) (*http.Response, error) { return respond(200, tokenBody(1)), nil })
	failures := 1
	var saved []string
	connection := app.Connection("conn_1", ConnectionOptions{
		RefreshToken: "nfr_0",
		OnTokenRefresh: func(_ context.Context, tokens ConnectionTokens) error {
			if failures > 0 {
				failures--
				return errors.New("disk dolu")
			}
			saved = append(saved, tokens.RefreshToken)
			return nil
		},
	})
	_, err := connection.Status(ctx)
	if got := apiError(t, err); got.Name != "token_persist_failed" || !strings.Contains(got.Message, "disk dolu") {
		t.Fatalf("hata %+v", got)
	}
	if _, err := connection.Status(ctx); err != nil {
		t.Fatalf("ikinci çağrı: %v", err)
	}
	if !reflect.DeepEqual(saved, []string{"nfr_1"}) || countToken(server.snapshot()) != 1 {
		t.Fatalf("saklanan %v, yenileme %d", saved, countToken(server.snapshot()))
	}
}

func TestConnectionEndpoints(t *testing.T) {
	connection, server, _ := openConnection(t, func(call recorded) (*http.Response, error) {
		if isToken(call) {
			return respond(200, tokenBody(1)), nil
		}
		return respond(200, `{"id":"e1","data":[]}`), nil
	})
	steps := []func() error{
		func() error { _, err := connection.Senders.List(ctx); return err },
		func() error { _, err := connection.Templates.List(ctx); return err },
		func() error {
			_, err := connection.Emails.Send(ctx, &SendEmailInput{From: "a@b.co", To: []string{"c@d.co"}, Subject: "s", HTML: "<p>x</p>"},
				SendEmailOptions{IdempotencyKey: "k1"})
			return err
		},
		func() error { _, err := connection.Emails.Get(ctx, "e1"); return err },
		func() error { _, err := connection.Emails.List(ctx, nil); return err },
	}
	for _, step := range steps {
		if err := step(); err != nil {
			t.Fatal(err)
		}
	}
	var got []string
	for _, call := range apiCalls(server.snapshot()) {
		parsed, _ := url.Parse(call.url)
		got = append(got, call.method+" "+parsed.Path)
	}
	want := []string{"GET /senders", "GET /templates", "POST /emails", "GET /emails/e1", "GET /emails"}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("çağrılar %v", got)
	}
}

func TestConnectionServerError(t *testing.T) {
	connection, _, _ := openConnection(t, func(call recorded) (*http.Response, error) {
		if isToken(call) {
			return respond(200, tokenBody(1)), nil
		}
		return respond(403, `{"statusCode":403,"name":"insufficient_scope","message":"scope"}`), nil
	})
	_, err := connection.Templates.List(ctx)
	if got := apiError(t, err); got.StatusCode != 403 || got.Name != "insufficient_scope" {
		t.Fatalf("hata %+v", got)
	}
}
