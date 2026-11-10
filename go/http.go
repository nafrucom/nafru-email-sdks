package nafruemail

import (
	"bytes"
	"context"
	"encoding/json"
	"errors"
	"io"
	"net"
	"net/http"
	"net/url"
	"os"
	"reflect"
	"strconv"
	"strings"
	"sync"
	"time"
)

// warnOutput, kullanımdan kaldırma uyarısının yazıldığı yer (testler değiştirir).
var warnOutput io.Writer = os.Stderr

const (
	baseBackoff = 300 * time.Millisecond
	maxBackoff  = 8 * time.Second
	// maxResponseBytes: bozuk ya da kötü niyetli bir ara katman belleği tüketemesin.
	maxResponseBytes = 10 << 20
)

func invalidArgument(message string) *Error {
	return &Error{Name: "invalid_argument", Message: message}
}

// validatePath: kimlik/e-posta gibi parçalar kaçırılır ama boş, "." ve ".." URL normalleştirmesiyle başka bir uca gider.
func validatePath(path string) error {
	for _, part := range strings.Split(strings.TrimPrefix(path, "/"), "/") {
		if part == "" || part == "." || part == ".." {
			return invalidArgument("Geçersiz yol parçası: boş, \".\" ya da \"..\" olamaz")
		}
	}
	return nil
}

// validateIdempotencyKey: denetim karakteri (CR/LF dahil) başlık enjeksiyonuna yol açar.
func validateIdempotencyKey(key string) error {
	for _, r := range key {
		if r < 0x20 || r == 0x7f {
			return invalidArgument("Geçersiz idempotencyKey: denetim karakteri içeremez")
		}
	}
	return nil
}

// validateBaseURL: anahtar ve belirteçler düz metin http üzerinden gitmesin; yalnız yerel geliştirme adreslerine izin var.
func validateBaseURL(raw, name string) error {
	parsed, err := url.Parse(raw)
	if err != nil || parsed.Host == "" {
		return invalidArgument(name + " geçerli bir mutlak adres olmalı")
	}
	if parsed.Scheme == "https" {
		return nil
	}
	host := parsed.Hostname()
	ip := net.ParseIP(host)
	local := host == "localhost" || strings.HasSuffix(host, ".localhost") || (ip != nil && ip.IsLoopback())
	if parsed.Scheme == "http" && local {
		return nil
	}
	return invalidArgument(name + " https kullanmalı (http yalnız localhost için)")
}

// noRedirects: API yönlendirme yapmaz; yönlendirmeyi izlemek Authorization başlığını başka bir sunucuya sızdırabilir.
func noRedirects(client *http.Client) *http.Client {
	copied := *client
	copied.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return &copied
}

type requestInput struct {
	method string
	path   string
	// query: sorgu yapısı (işaretçi olabilir); boş/sıfır alanlar atlanır.
	query any
	// body: nil ise gövde yok.
	body           any
	idempotencyKey string
}

// caller, bir isteği gönderip yanıtı out'a çözer; dönen hata her zaman *Error'dır.
type caller func(ctx context.Context, in requestInput, out any) error

type httpClient struct {
	baseURL    string
	client     *http.Client
	maxRetries int
	timeout    time.Duration
	userAgent  string
	// authorize her denemede belirteci verir; "" Authorization başlığı yok demektir.
	authorize func(ctx context.Context) (string, error)
	// deprecation, istemci örneği başına tek uyarı (kopyalar aynı işaretçiyi paylaşır).
	deprecation *sync.Once
}

// warnDeprecated: sunucu bu SDK sürümünü Deprecation başlığıyla işaretlediyse bir kez uyarır; çağrıyı asla bozmaz.
func (h *httpClient) warnDeprecated(header http.Header) {
	if header.Get("Deprecation") == "" || h.deprecation == nil {
		return
	}
	h.deprecation.Do(func() {
		message := "[nafru] Bu SDK sürümü (go " + Version + ") kullanımdan kaldırıldı; lütfen güncelleyin."
		if sunset := header.Get("Sunset"); sunset != "" {
			message += " Son tarih: " + sunset
		}
		if link := header.Get("Link"); link != "" {
			if start, end := strings.Index(link, "<"), strings.Index(link, ">"); start >= 0 && end > start {
				link = link[start+1 : end]
			}
			message += " Ayrıntı: " + link
		}
		_, _ = io.WriteString(warnOutput, message+"\n")
	})
}

// seg, yol parçasını kaçırır (encodeURIComponent gibi): kişi uçları e-postayı kimlik gibi kabul eder.
func seg(value string) string {
	return strings.ReplaceAll(url.QueryEscape(value), "+", "%20")
}

// serializeQuery, yapı alanlarını tanım sırasıyla (gömülü ListQuery önce) json etiket adlarıyla yazar; boş değerleri atlar.
func serializeQuery(query any) string {
	if query == nil {
		return ""
	}
	value := reflect.ValueOf(query)
	for value.Kind() == reflect.Pointer {
		if value.IsNil() {
			return ""
		}
		value = value.Elem()
	}
	var parts []string
	var walk func(v reflect.Value)
	walk = func(v reflect.Value) {
		t := v.Type()
		for i := 0; i < t.NumField(); i++ {
			field, fv := t.Field(i), v.Field(i)
			if field.Anonymous && fv.Kind() == reflect.Struct {
				walk(fv)
				continue
			}
			name := strings.Split(field.Tag.Get("json"), ",")[0]
			if name == "" || name == "-" || fv.IsZero() {
				continue
			}
			var text string
			switch fv.Kind() {
			case reflect.String:
				text = fv.String()
			case reflect.Int, reflect.Int64, reflect.Int32:
				text = strconv.FormatInt(fv.Int(), 10)
			case reflect.Bool:
				text = strconv.FormatBool(fv.Bool())
			default:
				continue
			}
			parts = append(parts, url.QueryEscape(name)+"="+url.QueryEscape(text))
		}
	}
	if value.Kind() == reflect.Struct {
		walk(value)
	}
	if len(parts) == 0 {
		return ""
	}
	return "?" + strings.Join(parts, "&")
}

// isSafeToRetry: GET ve DELETE yinelenebilir; POST/PATCH/PUT yalnız Idempotency-Key taşıyorsa (anahtarsız sunucu hatasında
// e-posta çift gidebilir). 429 her yöntemde yinelenir: istek işlenmeden reddedilmiştir.
func isSafeToRetry(in requestInput) bool {
	return in.method == http.MethodGet || in.method == http.MethodDelete || in.idempotencyKey != ""
}

func backoff(attempt int) time.Duration {
	wait := baseBackoff << attempt
	if wait > maxBackoff || wait <= 0 {
		return maxBackoff
	}
	return wait
}

func sleep(ctx context.Context, wait time.Duration) error {
	timer := time.NewTimer(wait)
	defer timer.Stop()
	select {
	case <-ctx.Done():
		return networkError("İstek iptal edildi")
	case <-timer.C:
		return nil
	}
}

func (h *httpClient) do(ctx context.Context, in requestInput, out any) error {
	var body []byte
	if in.body != nil {
		encoded, err := json.Marshal(in.body)
		if err != nil {
			return networkError("Gövde JSON'a çevrilemedi: " + err.Error())
		}
		body = encoded
	}
	if err := validatePath(in.path); err != nil {
		return err
	}
	if err := validateIdempotencyKey(in.idempotencyKey); err != nil {
		return err
	}
	target := strings.TrimRight(h.baseURL, "/") + in.path + serializeQuery(in.query)

	for attempt := 0; ; attempt++ {
		token, err := h.authorize(ctx)
		if err != nil {
			return err
		}
		last := attempt >= h.maxRetries
		response, payload, err := h.send(ctx, in, target, body, token)
		var sendErr *Error
		if errors.As(err, &sendErr) {
			return sendErr
		}
		if err != nil {
			if ctx.Err() != nil {
				return networkError("İstek iptal edildi")
			}
			if !last && isSafeToRetry(in) {
				if err := sleep(ctx, backoff(attempt)); err != nil {
					return err
				}
				continue
			}
			if errors.Is(err, context.DeadlineExceeded) {
				return timeoutError(h.timeout.Milliseconds())
			}
			var urlErr *url.Error
			if errors.As(err, &urlErr) {
				err = urlErr.Err
			}
			return networkError(err.Error())
		}

		h.warnDeprecated(response.Header)
		if response.StatusCode >= 200 && response.StatusCode < 300 {
			if out != nil && len(bytes.TrimSpace(payload)) > 0 {
				if err := json.Unmarshal(payload, out); err != nil {
					return networkError("Yanıt çözülemedi: " + err.Error())
				}
			}
			return nil
		}

		if response.StatusCode >= 300 && response.StatusCode < 400 {
			return &Error{StatusCode: response.StatusCode, Name: "unexpected_redirect",
				Message: "API yönlendirme döndürdü; güvenlik gereği izlenmedi (baseUrl'i denetleyin)"}
		}
		apiErr := parseError(response, payload)
		retryable := response.StatusCode == http.StatusTooManyRequests || (response.StatusCode >= 500 && isSafeToRetry(in))
		if retryable && !last {
			wait := backoff(attempt)
			if apiErr.RetryAfter != nil {
				wait = time.Duration(*apiErr.RetryAfter * float64(time.Second))
			}
			if wait > maxBackoff {
				wait = maxBackoff
			}
			if err := sleep(ctx, wait); err != nil {
				return err
			}
			continue
		}
		return apiErr
	}
}

// send tek bir denemedir; zaman aşımı gövdenin okunmasını da kapsar.
func (h *httpClient) send(ctx context.Context, in requestInput, target string, body []byte, token string) (*http.Response, []byte, error) {
	attemptCtx, cancel := context.WithTimeout(ctx, h.timeout)
	defer cancel()
	var reader io.Reader
	if body != nil {
		reader = bytes.NewReader(body)
	}
	request, err := http.NewRequestWithContext(attemptCtx, in.method, target, reader)
	if err != nil {
		return nil, nil, err
	}
	request.Header.Set("Accept", "application/json")
	request.Header.Set("User-Agent", h.userAgent)
	if token != "" {
		request.Header.Set("Authorization", "Bearer "+token)
	}
	if body != nil {
		request.Header.Set("Content-Type", "application/json")
	}
	if in.idempotencyKey != "" {
		request.Header.Set("Idempotency-Key", in.idempotencyKey)
	}
	response, err := h.client.Do(request)
	if err != nil {
		if attemptCtx.Err() == context.DeadlineExceeded {
			return nil, nil, context.DeadlineExceeded
		}
		return nil, nil, err
	}
	defer response.Body.Close()
	payload, err := io.ReadAll(io.LimitReader(response.Body, maxResponseBytes+1))
	if err != nil {
		if attemptCtx.Err() == context.DeadlineExceeded {
			return nil, nil, context.DeadlineExceeded
		}
		return nil, nil, err
	}
	if len(payload) > maxResponseBytes {
		return nil, nil, &Error{StatusCode: response.StatusCode, Name: "response_too_large", Message: "Yanıt 10 MB sınırını aştı"}
	}
	return response, payload, nil
}
