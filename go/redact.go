package nafruemail

import "fmt"

// Gizli değer taşıyan tipler fmt.Formatter uygular: %v, %+v, %#v, %s ve diğer fiiller anahtarı/belirteci asla basmaz
// (günlüğe yanlışlıkla yazılan bir yapı sızıntı olmasın). JSON kodlaması etkilenmez.

const redacted = "[REDACTED]"

func mask(secret string) string {
	if secret == "" {
		return ""
	}
	return redacted
}

// printRedacted, gizlisi temizlenmiş kopyayı (yöntemsiz yerel tip) aynı fiil ve bayraklarla yazar.
func printRedacted(f fmt.State, verb rune, value any) {
	fmt.Fprintf(f, fmt.FormatString(f, verb), value)
}

func (c Connect) Format(f fmt.State, verb rune) {
	type connect Connect
	c.creds.clientSecret = mask(c.creds.clientSecret)
	printRedacted(f, verb, connect(c))
}

func (o ConnectOptions) Format(f fmt.State, verb rune) {
	type connectOptions ConnectOptions
	o.ClientSecret = mask(o.ClientSecret)
	printRedacted(f, verb, connectOptions(o))
}

func (o ConnectionOptions) Format(f fmt.State, verb rune) {
	type connectionOptions ConnectionOptions
	o.RefreshToken = mask(o.RefreshToken)
	printRedacted(f, verb, connectionOptions(o))
}

func (t ConnectionTokens) Format(f fmt.State, verb rune) {
	type connectionTokens ConnectionTokens
	t.RefreshToken = mask(t.RefreshToken)
	printRedacted(f, verb, connectionTokens(t))
}

func (g ConnectionGrant) Format(f fmt.State, verb rune) {
	type connectionGrant ConnectionGrant
	g.RefreshToken = mask(g.RefreshToken)
	printRedacted(f, verb, connectionGrant(g))
}

func (a AuthorizeURL) Format(f fmt.State, verb rune) {
	type authorizeURL AuthorizeURL
	a.CodeVerifier = mask(a.CodeVerifier)
	printRedacted(f, verb, authorizeURL(a))
}

func (e ExchangeInput) Format(f fmt.State, verb rune) {
	type exchangeInput ExchangeInput
	e.Code, e.CodeVerifier = mask(e.Code), mask(e.CodeVerifier)
	printRedacted(f, verb, exchangeInput(e))
}

func (k CreatedAPIKey) Format(f fmt.State, verb rune) {
	type createdAPIKey CreatedAPIKey
	k.Token = mask(k.Token)
	printRedacted(f, verb, createdAPIKey(k))
}

func (w CreatedWebhook) Format(f fmt.State, verb rune) {
	type createdWebhook CreatedWebhook
	w.SigningSecret = mask(w.SigningSecret)
	printRedacted(f, verb, createdWebhook(w))
}

func (w WebhookDetail) Format(f fmt.State, verb rune) {
	type webhookDetail WebhookDetail
	w.SigningSecret = mask(w.SigningSecret)
	printRedacted(f, verb, webhookDetail(w))
}

func (v VerifyWebhookInput) Format(f fmt.State, verb rune) {
	type verifyWebhookInput VerifyWebhookInput
	v.Secret = mask(v.Secret)
	printRedacted(f, verb, verifyWebhookInput(v))
}

func (s BroadcastDataSource) Format(f fmt.State, verb rune) {
	type broadcastDataSource BroadcastDataSource
	s.Secret = mask(s.Secret)
	printRedacted(f, verb, broadcastDataSource(s))
}
