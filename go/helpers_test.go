package nafruemail

import (
	"encoding/json"
	"io"
	"net/http"
	"strings"
	"sync"
	"testing"
)

type recorded struct {
	method string
	url    string
	header http.Header
	body   string
}

func (r recorded) json(t *testing.T) any {
	t.Helper()
	if r.body == "" {
		return nil
	}
	var out any
	if err := json.Unmarshal([]byte(r.body), &out); err != nil {
		t.Fatalf("gövde JSON değil: %v", err)
	}
	return out
}

type roundTripFunc func(*http.Request) (*http.Response, error)

func (f roundTripFunc) RoundTrip(r *http.Request) (*http.Response, error) { return f(r) }

func respond(status int, body string, headers ...string) *http.Response {
	header := http.Header{"Content-Type": {"application/json"}}
	for i := 0; i+1 < len(headers); i += 2 {
		header.Set(headers[i], headers[i+1])
	}
	return &http.Response{
		StatusCode: status,
		Status:     http.StatusText(status),
		Header:     header,
		Body:       io.NopCloser(strings.NewReader(body)),
	}
}

func asJSON(value any) string {
	encoded, _ := json.Marshal(value)
	return string(encoded)
}

// mockServer, her isteği kaydeder ve route'un yanıtını döndürür.
type mockServer struct {
	mu    sync.Mutex
	calls []recorded
}

func (m *mockServer) client(route func(recorded) (*http.Response, error)) *http.Client {
	return &http.Client{Transport: roundTripFunc(func(r *http.Request) (*http.Response, error) {
		var body string
		if r.Body != nil {
			raw, _ := io.ReadAll(r.Body)
			body = string(raw)
		}
		call := recorded{method: r.Method, url: r.URL.String(), header: r.Header.Clone(), body: body}
		m.mu.Lock()
		m.calls = append(m.calls, call)
		m.mu.Unlock()
		return route(call)
	})}
}

func (m *mockServer) snapshot() []recorded {
	m.mu.Lock()
	defer m.mu.Unlock()
	return append([]recorded(nil), m.calls...)
}

// setup, yanıtları sırayla veren (sonuncusunu tekrarlayan) API anahtarlı istemci kurar.
func setup(t *testing.T, maxRetries int, responses ...func() (*http.Response, error)) (*Client, *mockServer) {
	t.Helper()
	server := &mockServer{}
	index := 0
	client, err := NewClient("key_test",
		WithBaseURL("https://api.test/"),
		WithMaxRetries(maxRetries),
		WithoutDevOutbox(),
		WithHTTPClient(server.client(func(recorded) (*http.Response, error) {
			next := responses[min(index, len(responses)-1)]
			index++
			return next()
		})),
	)
	if err != nil {
		t.Fatal(err)
	}
	return client, server
}

func ok(body string, headers ...string) func() (*http.Response, error) {
	return func() (*http.Response, error) { return respond(200, body, headers...), nil }
}

func status(code int, body string, headers ...string) func() (*http.Response, error) {
	return func() (*http.Response, error) { return respond(code, body, headers...), nil }
}
