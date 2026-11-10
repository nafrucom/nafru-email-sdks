package nafruemail

import (
	"bytes"
	"context"
	"encoding/json"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"strings"
	"testing"
	"time"
)

func TestPaginateFollowsAfterCursor(t *testing.T) {
	pages := []string{
		`{"object":"list","data":[{"id":"a"},{"id":"b"}],"has_more":true}`,
		`{"object":"list","data":[{"id":"c"}],"has_more":false}`,
	}
	n := 0
	client, server := setup(t, 0, func() (resp *http.Response, err error) {
		resp = respond(200, pages[n])
		n++
		return resp, nil
	})
	pager := Paginate(ctx, func(ctx context.Context, after string) (*ListResponse[Contact], error) {
		return client.Contacts.List(ctx, &ListContactsQuery{ListQuery: ListQuery{Limit: 2, After: after}})
	})
	var ids []string
	for pager.Next() {
		ids = append(ids, pager.Item().ID)
	}
	if pager.Err() != nil || !reflect.DeepEqual(ids, []string{"a", "b", "c"}) {
		t.Fatalf("ids %v, hata %v", ids, pager.Err())
	}
	var urls []string
	for _, call := range server.snapshot() {
		urls = append(urls, call.url)
	}
	if !reflect.DeepEqual(urls, []string{"https://api.test/contacts?limit=2", "https://api.test/contacts?limit=2&after=b"}) {
		t.Fatalf("urls %v", urls)
	}
}

func TestPaginateStopsWithError(t *testing.T) {
	client, _ := setup(t, 0, status(401, `{"statusCode":401,"name":"unauthorized","message":"anahtar yok"}`))
	pager := Paginate(ctx, func(ctx context.Context, after string) (*ListResponse[Contact], error) {
		return client.Contacts.List(ctx, &ListContactsQuery{ListQuery: ListQuery{After: after}})
	})
	for pager.Next() {
		t.Fatal("öğe beklenmiyordu")
	}
	if got := apiError(t, pager.Err()); got.StatusCode != 401 || got.Message != "anahtar yok" {
		t.Fatalf("hata %+v", got)
	}
}

func TestWebhookSharedVector(t *testing.T) {
	raw, err := os.ReadFile("../webhook-test-vector.json")
	if err != nil {
		t.Fatal(err)
	}
	var vector struct {
		Secret, ID, Timestamp, Payload, Signature string
		NowSeconds                                int64 `json:"now_seconds"`
	}
	if err := json.Unmarshal(raw, &vector); err != nil {
		t.Fatal(err)
	}
	input := VerifyWebhookInput{
		Payload: vector.Payload,
		Headers: WebhookHeaders{ID: vector.ID, Timestamp: vector.Timestamp, Signature: vector.Signature},
		Secret:  vector.Secret,
		Now:     time.Unix(vector.NowSeconds, 0),
	}
	if valid, err := VerifyWebhook(input); err != nil || !valid {
		t.Fatalf("vektör doğrulanmadı: %v %v", valid, err)
	}

	tampered := input
	tampered.Payload += " "
	if valid, _ := VerifyWebhook(tampered); valid {
		t.Fatal("değiştirilmiş gövde kabul edildi")
	}

	rotated := input
	rotated.Headers.Signature = "v1,bozuk " + vector.Signature + " v2,x"
	if valid, _ := VerifyWebhook(rotated); !valid {
		t.Fatal("çoklu imzadan biri yeterli olmalı")
	}

	stale := input
	stale.Now = time.Unix(vector.NowSeconds+301, 0)
	if valid, _ := VerifyWebhook(stale); valid {
		t.Fatal("eski zaman damgası kabul edildi")
	}

	garbage := input
	garbage.Headers.Timestamp = "abc"
	if valid, _ := VerifyWebhook(garbage); valid {
		t.Fatal("bozuk zaman damgası kabul edildi")
	}

	badSecret := input
	badSecret.Secret = "sec"
	if _, err := VerifyWebhook(badSecret); err == nil || !strings.Contains(err.Error(), "whsec_") {
		t.Fatalf("bozuk anahtar hatası yok: %v", err)
	}
}

func TestDevOutboxWritesInsteadOfSending(t *testing.T) {
	dir := t.TempDir()
	var log bytes.Buffer
	previous := devOutput
	devOutput = &log
	defer func() { devOutput = previous }()

	client, err := NewClient("k", WithBaseURL("https://api.test"), WithDevOutbox(dir),
		WithHTTPClient((&mockServer{}).client(func(recorded) (*http.Response, error) {
			t.Fatal("istek gönderilmemeli")
			return nil, nil
		})))
	if err != nil {
		t.Fatal(err)
	}
	sent, err := client.Emails.Send(ctx, &SendEmailInput{From: "a@x.com", To: []string{"b@y.com", "c@y.com"}, Subject: "Merhaba",
		HTML: "<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>"})
	if err != nil || !strings.HasPrefix(sent.ID, "dev_") {
		t.Fatalf("sonuç %+v, hata %v", sent, err)
	}
	batch, err := client.Emails.Batch(ctx, []BatchEmailItem{{From: "a@x.com", To: []string{"d@y.com"}, Subject: "S", Text: "düz"}})
	if err != nil || len(batch.Data) != 1 {
		t.Fatalf("toplu %+v, hata %v", batch, err)
	}

	txt, _ := filepath.Glob(filepath.Join(dir, "*.txt"))
	html, _ := filepath.Glob(filepath.Join(dir, "*.html"))
	if len(txt) != 2 || len(html) != 2 {
		t.Fatalf("dosyalar txt=%d html=%d", len(txt), len(html))
	}
	base := ""
	for _, path := range txt {
		if strings.Contains(path, sent.ID) {
			base = strings.TrimSuffix(path, ".txt")
		}
	}
	text, _ := os.ReadFile(base + ".txt")
	for _, want := range []string{"To: b@y.com, c@y.com", "Subject: Merhaba", "Selam Ali\n& hoş geldin"} {
		if !strings.Contains(string(text), want) {
			t.Errorf(".txt %q içermiyor:\n%s", want, text)
		}
	}
	if page, _ := os.ReadFile(base + ".html"); !strings.Contains(string(page), "<b>Ali</b>") {
		t.Errorf(".html: %s", page)
	}
	if !strings.Contains(log.String(), base+".txt") {
		t.Errorf("konsol yolu basmadı: %s", log.String())
	}
}

func TestDevOutboxDefaultOnlyInDevelopment(t *testing.T) {
	t.Setenv("NODE_ENV", "development")
	if got := resolveDevOutbox("", false); got != ".nafru/emails" {
		t.Fatalf("varsayılan %q", got)
	}
	if got := resolveDevOutbox("", true); got != "" {
		t.Fatalf("kapalı %q", got)
	}
	t.Setenv("NODE_ENV", "production")
	if got := resolveDevOutbox("", false); got != "" {
		t.Fatalf("üretimde %q", got)
	}
}
