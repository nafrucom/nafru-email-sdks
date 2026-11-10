package nafruemail

import (
	"bytes"
	"context"
	"errors"
	"net/http"
	"reflect"
	"strings"
	"testing"
	"time"
)

var ctx = context.Background()

func apiError(t *testing.T, err error) *Error {
	t.Helper()
	var apiErr *Error
	if !errors.As(err, &apiErr) {
		t.Fatalf("*Error bekleniyordu, gelen: %v", err)
	}
	return apiErr
}

func TestSendHeadersAndIdempotency(t *testing.T) {
	client, server := setup(t, 0, ok(`{"id":"e1"}`))
	result, err := client.Emails.Send(ctx, &SendEmailInput{From: "a@x.test", To: []string{"b@x.test"}, Subject: "s", Text: "t"},
		SendEmailOptions{IdempotencyKey: "k-1"})
	if err != nil || result.ID != "e1" {
		t.Fatalf("sonuç %+v, hata %v", result, err)
	}
	call := server.snapshot()[0]
	if call.url != "https://api.test/emails" || call.method != "POST" {
		t.Fatalf("istek %s %s", call.method, call.url)
	}
	checks := map[string]string{
		"Authorization":   "Bearer key_test",
		"Content-Type":    "application/json",
		"User-Agent":      "nafru-email-go/" + Version,
		"Idempotency-Key": "k-1",
	}
	for name, want := range checks {
		if got := call.header.Get(name); got != want {
			t.Errorf("%s = %q, beklenen %q", name, got, want)
		}
	}
	want := map[string]any{"from": "a@x.test", "to": []any{"b@x.test"}, "subject": "s", "text": "t"}
	if got := call.json(t); !reflect.DeepEqual(got, want) {
		t.Errorf("gövde %v", got)
	}
}

func TestQuerySkipsEmptyValues(t *testing.T) {
	client, server := setup(t, 0, ok(`{"object":"list","data":[],"has_more":false}`))
	if _, err := client.Contacts.List(ctx, &ListContactsQuery{ListQuery: ListQuery{Limit: 5}, Search: "ali"}); err != nil {
		t.Fatal(err)
	}
	if got := server.snapshot()[0].url; got != "https://api.test/contacts?limit=5&search=ali" {
		t.Fatalf("url %s", got)
	}
}

func TestParsesErrorBody(t *testing.T) {
	body := `{"statusCode":422,"name":"validation_error","message":"Geçersiz","errors":[{"field":"to","message":"zorunlu","i18nTranslationKey":"k"}]}`
	client, _ := setup(t, 0, status(422, body))
	_, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"})
	got := apiError(t, err)
	want := &Error{StatusCode: 422, Name: "validation_error", Message: "Geçersiz",
		Errors: []FieldError{{Field: "to", Message: "zorunlu", I18nTranslationKey: "k"}}}
	if !reflect.DeepEqual(got, want) {
		t.Fatalf("hata %+v", got)
	}
}

func TestNonStandardErrorFromStatus(t *testing.T) {
	client, _ := setup(t, 0, func() (*http.Response, error) {
		r := respond(502, "<html>bad gateway</html>")
		r.Status = "502 Bad Gateway"
		return r, nil
	})
	_, err := client.Emails.Get(ctx, "e1")
	got := apiError(t, err)
	if got.StatusCode != 502 || got.Name != "application_error" || got.Message != "Bad Gateway" {
		t.Fatalf("hata %+v", got)
	}
}

func TestNetworkError(t *testing.T) {
	client, _ := setup(t, 0, func() (*http.Response, error) { return nil, errors.New("fetch failed") })
	_, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"})
	got := apiError(t, err)
	if got.StatusCode != 0 || got.Name != "application_error" || got.Message != "fetch failed" {
		t.Fatalf("hata %+v", got)
	}
}

func TestRetries429WithRetryAfter(t *testing.T) {
	limited := status(429, `{"statusCode":429,"name":"rate_limit_exceeded","message":"yavaş"}`, "Retry-After", "0")
	client, server := setup(t, 2, limited, ok(`{"id":"e1"}`))
	result, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"})
	if err != nil || result.ID != "e1" || len(server.snapshot()) != 2 {
		t.Fatalf("sonuç %+v, hata %v, çağrı %d", result, err, len(server.snapshot()))
	}
}

func TestRetry429ExhaustedReturnsRetryAfter(t *testing.T) {
	limited := status(429, `{"statusCode":429,"name":"rate_limit_exceeded","message":"yavaş"}`, "Retry-After", "0")
	client, server := setup(t, 1, limited)
	_, err := client.Emails.Get(ctx, "e1")
	got := apiError(t, err)
	if got.StatusCode != 429 || got.Name != "rate_limit_exceeded" || got.RetryAfter == nil || *got.RetryAfter != 0 {
		t.Fatalf("hata %+v", got)
	}
	if len(server.snapshot()) != 2 {
		t.Fatalf("çağrı %d", len(server.snapshot()))
	}
}

func TestGet5xxRetriedPostWithoutKeyNot(t *testing.T) {
	down := status(500, `{"statusCode":500,"name":"application_error","message":"x"}`)
	client, server := setup(t, 1, down, ok(`{"id":"e1"}`))
	if email, err := client.Emails.Get(ctx, "e1"); err != nil || email.ID != "e1" || len(server.snapshot()) != 2 {
		t.Fatalf("GET yeniden denenmedi: %v", err)
	}

	client, server = setup(t, 1, down, ok(`{"id":"e1"}`))
	_, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"})
	if apiError(t, err).StatusCode != 500 || len(server.snapshot()) != 1 {
		t.Fatalf("anahtarsız POST yeniden denendi")
	}
}

func TestIdempotentPostRetriedAfter5xx(t *testing.T) {
	down := status(503, `{"statusCode":503,"name":"application_error","message":"x"}`)
	client, server := setup(t, 1, down, ok(`{"id":"e1"}`))
	result, err := client.Emails.Send(ctx, &SendEmailInput{To: []string{"x"}, Text: "t"}, SendEmailOptions{IdempotencyKey: "k-1"})
	calls := server.snapshot()
	if err != nil || result.ID != "e1" || len(calls) != 2 || calls[1].header.Get("Idempotency-Key") != "k-1" {
		t.Fatalf("sonuç %+v, hata %v", result, err)
	}
}

func TestTimeout(t *testing.T) {
	client, err := NewClient("k", WithBaseURL("https://api.test"), WithMaxRetries(0), WithTimeout(20*time.Millisecond),
		WithHTTPClient(&http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
			<-r.Context().Done()
			return nil, r.Context().Err()
		})}))
	if err != nil {
		t.Fatal(err)
	}
	_, err = client.Emails.Get(ctx, "e1")
	if got := apiError(t, err); got.StatusCode != 0 || got.Name != "timeout_error" {
		t.Fatalf("hata %+v", got)
	}
}

func TestAPIKeyRequired(t *testing.T) {
	t.Setenv("NAFRU_API_KEY", "")
	if _, err := NewClient("", WithBaseURL("https://x")); err == nil || !strings.Contains(err.Error(), "apiKey") {
		t.Fatalf("apiKey hatası yok: %v", err)
	}
}

// Anahtar verilmezse NAFRU_API_KEY okunur; BaseURL verilmezse DefaultBaseURL.
func TestAPIKeyFromEnvAndDefaultBaseURL(t *testing.T) {
	t.Setenv("NAFRU_API_KEY", "nafru_env")
	server := &mockServer{}
	client, err := NewClient("", WithMaxRetries(0),
		WithHTTPClient(server.client(func(recorded) (*http.Response, error) { return respond(200, `{"id":"e1"}`), nil })))
	if err != nil {
		t.Fatal(err)
	}
	if _, err := client.Emails.Get(ctx, "e1"); err != nil {
		t.Fatal(err)
	}
	call := server.snapshot()[0]
	if call.header.Get("Authorization") != "Bearer nafru_env" {
		t.Fatalf("ortam anahtarı kullanılmadı: %q", call.header.Get("Authorization"))
	}
	if call.url != DefaultBaseURL+"/emails/e1" {
		t.Fatalf("varsayılan adres kullanılmadı: %s", call.url)
	}
}

func TestDeprecationWarnsOncePerClient(t *testing.T) {
	var out bytes.Buffer
	previous := warnOutput
	warnOutput = &out
	defer func() { warnOutput = previous }()

	deprecated := ok(`{"id":"e1"}`, "Deprecation", "true", "Sunset", "Wed, 01 Jul 2027 00:00:00 GMT",
		"Link", `<https://github.com/nafrucom/nafru-email-sdks/releases>; rel="deprecation"`)
	client, _ := setup(t, 0, deprecated)
	for i := 0; i < 2; i++ {
		if _, err := client.Emails.Get(ctx, "e1"); err != nil {
			t.Fatalf("uyarı çağrıyı bozdu: %v", err)
		}
	}
	want := "[nafru] Bu SDK sürümü (go " + Version + ") kullanımdan kaldırıldı; lütfen güncelleyin." +
		" Son tarih: Wed, 01 Jul 2027 00:00:00 GMT Ayrıntı: https://github.com/nafrucom/nafru-email-sdks/releases\n"
	if out.String() != want {
		t.Fatalf("uyarı %q", out.String())
	}
}
