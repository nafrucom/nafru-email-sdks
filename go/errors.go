package nafruemail

import (
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"strings"
)

// FieldError, 422 yanıtındaki alan ayrıntısıdır.
type FieldError struct {
	Field              string `json:"field"`
	Message            string `json:"message"`
	I18nTranslationKey string `json:"i18nTranslationKey,omitempty"`
}

// Error, her başarısız çağrının döndürdüğü hatadır. Name sunucunun hata adıdır (validation_error, rate_limit_exceeded,
// not_found, …); ağ ve zaman aşımı için application_error / timeout_error.
type Error struct {
	// StatusCode ağ ve zaman aşımı hatalarında 0'dır (TS SDK'daki null).
	StatusCode int          `json:"statusCode"`
	Name       string       `json:"name"`
	Message    string       `json:"message"`
	Errors     []FieldError `json:"errors,omitempty"`
	// RetryAfter, 429 yanıtındaki retry-after (saniye); başlık yoksa nil.
	RetryAfter *float64 `json:"retryAfter,omitempty"`
}

func (e *Error) Error() string {
	if e.StatusCode == 0 {
		return fmt.Sprintf("nafru: %s: %s", e.Name, e.Message)
	}
	return fmt.Sprintf("nafru: %s (%d): %s", e.Name, e.StatusCode, e.Message)
}

var namesByStatus = map[int]string{
	400: "invalid_request",
	401: "unauthorized",
	403: "forbidden",
	404: "not_found",
	409: "conflict",
	413: "payload_too_large",
	422: "validation_error",
	429: "rate_limit_exceeded",
}

func nameForStatus(status int) string {
	if name, ok := namesByStatus[status]; ok {
		return name
	}
	return "application_error"
}

func networkError(message string) *Error {
	return &Error{Name: "application_error", Message: message}
}

func timeoutError(timeoutMs int64) *Error {
	return &Error{Name: "timeout_error", Message: fmt.Sprintf("İstek %d ms içinde tamamlanmadı", timeoutMs)}
}

func readRetryAfter(header http.Header) *float64 {
	raw := header.Get("retry-after")
	if raw == "" {
		return nil
	}
	value, err := strconv.ParseFloat(strings.TrimSpace(raw), 64)
	if err != nil || value < 0 {
		return nil
	}
	return &value
}

// parseError, standart gövde (statusCode, name, message, errors) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde).
func parseError(response *http.Response, payload []byte) *Error {
	retryAfter := readRetryAfter(response.Header)
	status := response.StatusCode
	var body map[string]any
	if json.Unmarshal(payload, &body) == nil {
		if message, ok := body["message"].(string); ok {
			out := &Error{StatusCode: status, Name: nameForStatus(status), Message: message, RetryAfter: retryAfter}
			if code, ok := body["statusCode"].(float64); ok {
				out.StatusCode = int(code)
			}
			if name, ok := body["name"].(string); ok {
				out.Name = name
			}
			if list, ok := body["errors"].([]any); ok {
				for _, item := range list {
					entry, ok := item.(map[string]any)
					if !ok {
						continue
					}
					field, _ := entry["field"].(string)
					msg, _ := entry["message"].(string)
					key, _ := entry["i18nTranslationKey"].(string)
					out.Errors = append(out.Errors, FieldError{Field: field, Message: msg, I18nTranslationKey: key})
				}
			}
			return out
		}
	}
	message := strings.TrimSpace(strings.TrimPrefix(response.Status, strconv.Itoa(status)))
	if message == "" {
		message = fmt.Sprintf("HTTP %d", status)
	}
	return &Error{StatusCode: status, Name: nameForStatus(status), Message: message, RetryAfter: retryAfter}
}
