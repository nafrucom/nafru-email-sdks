package nafruemail

import (
	"fmt"
	"net/http"
	"strings"
	"testing"
	"time"
)

func TestBaseURLMustBeHTTPS(t *testing.T) {
	for _, base := range []string{"http://api.example.com/api", "ftp://api.example.com", "http://10.0.0.1/api", "api.example.com"} {
		if _, err := NewClient("k", WithBaseURL(base)); err == nil || apiError(t, err).Name != "invalid_argument" {
			t.Errorf("%s kabul edildi: %v", base, err)
		}
	}
	for _, base := range []string{"https://api.example.com/api", "http://localhost:48787/api", "http://app.localhost/api",
		"http://127.0.0.1:8080/api", "http://127.4.5.6/api", "http://[::1]:8080/api"} {
		if _, err := NewClient("k", WithBaseURL(base)); err != nil {
			t.Errorf("%s reddedildi: %v", base, err)
		}
	}
	if _, err := NewConnect(ConnectOptions{ClientID: "a", ClientSecret: "s", BaseURL: "http://evil.example/api"}); err == nil {
		t.Error("Connect http baseUrl kabul etti")
	}
	if _, err := NewConnect(ConnectOptions{ClientID: "a", ClientSecret: "s", WebURL: "http://evil.example"}); err == nil {
		t.Error("Connect http webUrl kabul etti")
	}
}

func TestRedirectIsNotFollowed(t *testing.T) {
	client, server := setup(t, 2, status(302, ``, "Location", "https://evil.example/steal"))
	_, err := client.Emails.Get(ctx, "e1")
	if got := apiError(t, err); got.Name != "unexpected_redirect" || got.StatusCode != 302 {
		t.Fatalf("hata %+v", got)
	}
	if n := len(server.snapshot()); n != 1 {
		t.Fatalf("yönlendirme izlendi ya da yeniden denendi: %d çağrı", n)
	}
	// Kullanıcının verdiği istemci de yönlendirme izlememeli (gerçek http.Client.Do yolu).
	var hops int
	transport := roundTripFunc(func(r *http.Request) (*http.Response, error) {
		hops++
		return respond(307, ``, "Location", "https://evil.example/steal"), nil
	})
	own, _ := NewClient("k", WithMaxRetries(0), WithHTTPClient(&http.Client{Transport: transport}))
	if _, err := own.Emails.Get(ctx, "e1"); apiError(t, err).Name != "unexpected_redirect" || hops != 1 {
		t.Fatalf("hops %d, hata %v", hops, err)
	}
}

func TestPathSegmentsRejected(t *testing.T) {
	client, server := setup(t, 0, ok(`{}`))
	for _, id := range []string{"", ".", ".."} {
		_, err := client.Emails.Get(ctx, id)
		if got := apiError(t, err); got.Name != "invalid_argument" {
			t.Errorf("%q: %+v", id, got)
		}
		_, err = client.Contacts.Segments.Remove(ctx, "c1", id)
		if got := apiError(t, err); got.Name != "invalid_argument" {
			t.Errorf("segment %q: %+v", id, got)
		}
	}
	if len(server.snapshot()) != 0 {
		t.Fatal("istek gönderilmemeliydi")
	}
	// Nokta içeren ama "." / ".." olmayan değerler geçerlidir.
	if _, err := client.Contacts.Get(ctx, "a.b@x.test"); err != nil {
		t.Fatal(err)
	}
}

func TestIdempotencyKeyControlCharsRejected(t *testing.T) {
	client, server := setup(t, 0, ok(`{"id":"e1"}`))
	for _, key := range []string{"a\r\nX-Evil: 1", "a\nb", "a\x00b", "a\tb", "a\x7fb"} {
		_, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"}, SendEmailOptions{IdempotencyKey: key})
		if got := apiError(t, err); got.Name != "invalid_argument" {
			t.Errorf("%q: %+v", key, got)
		}
	}
	if len(server.snapshot()) != 0 {
		t.Fatal("istek gönderilmemeliydi")
	}
}

func TestResponseTooLarge(t *testing.T) {
	big := `{"id":"` + strings.Repeat("a", maxResponseBytes) + `"}`
	client, _ := setup(t, 0, ok(big))
	if _, err := client.Emails.Get(ctx, "e1"); apiError(t, err).Name != "response_too_large" {
		t.Fatalf("hata %v", err)
	}
}

func TestSecretsAreRedacted(t *testing.T) {
	const apiKey, secret, refresh = "nafru_supersecretkey", "nfs_clientsecret", "nfr_refreshtoken"
	client, _ := NewClient(apiKey)
	connect, _ := NewConnect(ConnectOptions{ClientID: "app_x", ClientSecret: secret})
	values := []any{
		client, *client, connect, *connect,
		ConnectOptions{ClientID: "app_x", ClientSecret: secret},
		&ConnectionGrant{ConnectionID: "conn_1", RefreshToken: refresh},
		ConnectionTokens{RefreshToken: refresh},
		ConnectionOptions{RefreshToken: refresh},
		connect.Connection("conn_1", ConnectionOptions{RefreshToken: refresh}),
		CreatedAPIKey{ID: "k1", Token: apiKey},
		CreatedWebhook{ID: "w1", SigningSecret: "whsec_" + secret},
		VerifyWebhookInput{Secret: "whsec_" + secret},
	}
	for _, value := range values {
		for _, verb := range []string{"%v", "%+v", "%#v", "%s", "%d", "%x"} {
			out := fmt.Sprintf(verb, value)
			for _, s := range []string{apiKey, secret, refresh} {
				if strings.Contains(out, s) {
					t.Errorf("%s %T gizliyi sızdırdı: %s", verb, value, out)
				}
			}
		}
	}
	if out := fmt.Sprintf("%+v", ConnectionGrant{ConnectionID: "conn_1", RefreshToken: refresh}); !strings.Contains(out, "conn_1") ||
		!strings.Contains(out, redacted) {
		t.Fatalf("gizli olmayan alanlar görünmeli: %s", out)
	}
}

func TestWebhookHostileHeaders(t *testing.T) {
	secret := "whsec_bmFmcnUtc2RrLXRlc3Qtc2VjcmV0LTMyLWJ5dGVzISE="
	now := time.Unix(1767225600, 0)
	if valid, err := VerifyWebhook(VerifyWebhookInput{Payload: "{}", Secret: secret, Now: now}); err != nil || valid {
		t.Fatalf("boş başlıklar: %v %v", valid, err)
	}
	// İlk 32 girdiden sonrası yok sayılır (doğru imza 33. sırada olsa bile).
	good := "v1,IR0V8GoLqxeRmUovKQynVfhF0WcRu5CnCzS5zSz14TU="
	many := strings.Repeat("v1,AAAA ", 32) + good
	input := VerifyWebhookInput{
		Payload: `{"type":"email.delivered","data":{"email_id":"em_123"}}`,
		Headers: WebhookHeaders{ID: "msg_2KWPBgLlAfxdpx2AI54pPJ85f4W", Timestamp: "1767225600", Signature: many},
		Secret:  secret, Now: now,
	}
	if valid, _ := VerifyWebhook(input); valid {
		t.Fatal("33. imza değerlendirilmemeliydi")
	}
	input.Headers.Signature = strings.Repeat("v1,AAAA ", 31) + good
	if valid, _ := VerifyWebhook(input); !valid {
		t.Fatal("32. imza değerlendirilmeliydi")
	}
	// Tolerans iki yönde de geçerli: gelecekteki zaman damgası da reddedilir.
	input.Headers.Signature = good
	input.Now = time.Unix(1767225600-301, 0)
	if valid, _ := VerifyWebhook(input); valid {
		t.Fatal("ileri tarihli zaman damgası kabul edildi")
	}
}
