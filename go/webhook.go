package nafruemail

import (
	"crypto/hmac"
	"crypto/sha256"
	"encoding/base64"
	"errors"
	"strconv"
	"strings"
	"time"
)

// Svix / Standard Webhooks uyumlu imza doğrulama.
//
//	imzalanan = <svix-id>.<svix-timestamp>.<ham gövde>
//	anahtar   = whsec_ sonrası base64 çözülmüş signing_secret
//	başlık    = v1,<base64 HMAC-SHA256> (anahtar döndürmede boşlukla ayrılmış birden çok imza)

const (
	secretPrefix            = "whsec_"
	defaultToleranceSeconds = 300
	maxSignatures           = 32
)

type WebhookHeaders struct {
	ID        string // svix-id
	Timestamp string // svix-timestamp
	Signature string // svix-signature
}

type VerifyWebhookInput struct {
	// Payload HAM istek gövdesi: ayrıştırılıp yeniden dizilmiş JSON imzayı bozar.
	Payload string
	Headers WebhookHeaders
	// Secret webhook'un signing_secret değeri (whsec_…).
	Secret string
	// ToleranceSeconds tekrar saldırısına karşı izin verilen zaman farkı; 0 ise 300.
	ToleranceSeconds int64
	// Now şimdiki zaman; sıfırsa time.Now() (testler için).
	Now time.Time
}

// VerifyWebhook, imza ve zaman damgası geçerliyse true döner. Bozuk imza ya da zaman damgası false; bozuk Secret hata
// döndürür (yapılandırma hatası).
func VerifyWebhook(input VerifyWebhookInput) (bool, error) {
	if !strings.HasPrefix(input.Secret, secretPrefix) {
		return false, errors.New("Geçersiz imza anahtarı: whsec_ ile başlamalı")
	}
	key, err := base64.StdEncoding.DecodeString(strings.TrimPrefix(input.Secret, secretPrefix))
	if err != nil {
		return false, errors.New("Geçersiz imza anahtarı: base64 çözülemedi")
	}

	timestamp, err := strconv.ParseInt(input.Headers.Timestamp, 10, 64)
	if err != nil {
		return false, nil
	}
	tolerance := input.ToleranceSeconds
	if tolerance == 0 {
		tolerance = defaultToleranceSeconds
	}
	now := input.Now
	if now.IsZero() {
		now = time.Now()
	}
	if diff := now.Unix() - timestamp; diff > tolerance || -diff > tolerance {
		return false, nil
	}

	mac := hmac.New(sha256.New, key)
	mac.Write([]byte(input.Headers.ID + "." + input.Headers.Timestamp + "." + input.Payload))
	expected := mac.Sum(nil)

	// Anahtar döndürmede birkaç imza gelir; sınırsız liste işlemciyi yormasın: ilk 32'den sonrası yok sayılır.
	candidates := strings.SplitN(input.Headers.Signature, " ", maxSignatures+1)
	if len(candidates) > maxSignatures {
		candidates = candidates[:maxSignatures]
	}
	for _, candidate := range candidates {
		version, value, ok := strings.Cut(candidate, ",")
		if !ok || version != "v1" || value == "" {
			continue
		}
		signature, err := base64.StdEncoding.DecodeString(value)
		if err != nil {
			continue
		}
		// hmac.Equal sabit zamanlı karşılaştırır.
		if hmac.Equal(signature, expected) {
			return true, nil
		}
	}
	return false, nil
}
