package nafruemail

import (
	"crypto/rand"
	"encoding/json"
	"fmt"
	"io"
	"math/big"
	"os"
	"path/filepath"
	"regexp"
	"strconv"
	"strings"
	"time"
)

// devOutput, dev çıkış kutusunun konsol çıktısı (testler değiştirir).
var devOutput io.Writer = os.Stdout

// resolveDevOutbox: dir verilmezse yalnız NODE_ENV=development iken .nafru/emails; "" gerçek gönderim demektir.
func resolveDevOutbox(dir string, disabled bool) string {
	if disabled {
		return ""
	}
	if dir != "" {
		return dir
	}
	if os.Getenv("NODE_ENV") == "development" {
		return ".nafru/emails"
	}
	return ""
}

type devEmail struct {
	from, subject, scheduledAt, html, text string
	to, cc, bcc, replyTo                   []string
	template                               *EmailTemplate
}

func devEmailFromSend(in *SendEmailInput) devEmail {
	return devEmail{from: in.From, to: in.To, cc: in.Cc, bcc: in.Bcc, replyTo: in.ReplyTo, subject: in.Subject,
		scheduledAt: in.ScheduledAt, html: in.HTML, text: in.Text, template: in.Template}
}

func devEmailFromBatch(in *BatchEmailItem) devEmail {
	return devEmail{from: in.From, to: in.To, cc: in.Cc, bcc: in.Bcc, replyTo: in.ReplyTo, subject: in.Subject,
		scheduledAt: in.ScheduledAt, html: in.HTML, text: in.Text}
}

var (
	styleTags   = regexp.MustCompile(`(?is)<style[^>]*>.*?</style>|<script[^>]*>.*?</script>`)
	breakTags   = regexp.MustCompile(`(?i)<br\s*/?>|</(p|div|h[1-6]|li|tr)>`)
	anyTag      = regexp.MustCompile(`<[^>]+>`)
	manyNewline = regexp.MustCompile(`\n{3,}`)
	entities    = strings.NewReplacer("&nbsp;", " ", "&lt;", "<", "&gt;", ">", "&quot;", `"`, "&amp;", "&")
	escapeHTML  = strings.NewReplacer("&", "&amp;", "<", "&lt;", ">", "&gt;", `"`, "&quot;")
)

// shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
func htmlToText(html string) string {
	text := styleTags.ReplaceAllString(html, "")
	text = breakTags.ReplaceAllString(text, "\n")
	text = anyTag.ReplaceAllString(text, "")
	text = entities.Replace(text)
	return strings.TrimSpace(manyNewline.ReplaceAllString(text, "\n\n"))
}

func (e devEmail) body() string {
	switch {
	case e.text != "":
		return e.text
	case e.html != "":
		return htmlToText(e.html)
	case e.template != nil:
		variables := e.template.Variables
		if variables == nil {
			variables = map[string]any{}
		}
		encoded, _ := json.MarshalIndent(variables, "", "  ")
		return fmt.Sprintf("[şablon %s]\n%s", e.template.ID, encoded)
	}
	return ""
}

func randomBase36(n int) string {
	const alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
	out := make([]byte, n)
	for i := range out {
		index, _ := rand.Int(rand.Reader, big.NewInt(int64(len(alphabet))))
		out[i] = alphabet[index.Int64()]
	}
	return string(out)
}

// writeDevEmail, e-postayı göndermeden dir altına .txt ve .html olarak yazar, yolu ve düz metni konsola basar.
func writeDevEmail(dir string, email devEmail) (*SendEmailResponse, error) {
	now := time.Now().UTC()
	id := "dev_" + strconv.FormatInt(now.UnixMilli(), 36) + randomBase36(6)
	absolute, err := filepath.Abs(dir)
	if err != nil {
		return nil, networkError("Dev çıkış kutusu yazılamadı: " + err.Error())
	}
	stamp := strings.NewReplacer(":", "-", ".", "-").Replace(now.Format("2006-01-02T15:04:05.000Z"))
	base := filepath.Join(absolute, stamp+"-"+id)

	headers := []string{"From: " + email.from, "To: " + strings.Join(email.to, ", ")}
	if len(email.cc) > 0 {
		headers = append(headers, "Cc: "+strings.Join(email.cc, ", "))
	}
	if len(email.bcc) > 0 {
		headers = append(headers, "Bcc: "+strings.Join(email.bcc, ", "))
	}
	if len(email.replyTo) > 0 {
		headers = append(headers, "Reply-To: "+strings.Join(email.replyTo, ", "))
	}
	headers = append(headers, "Subject: "+email.subject)
	if email.scheduledAt != "" {
		headers = append(headers, "Scheduled-At: "+email.scheduledAt)
	}
	body := email.body()
	text := strings.Join(headers, "\n") + "\n\n" + body + "\n"
	html := email.html
	if html == "" {
		html = "<pre>" + escapeHTML.Replace(body) + "</pre>"
	}

	if err := os.MkdirAll(absolute, 0o755); err != nil {
		return nil, networkError("Dev çıkış kutusu yazılamadı: " + err.Error())
	}
	if err := os.WriteFile(base+".txt", []byte(text), 0o644); err != nil {
		return nil, networkError("Dev çıkış kutusu yazılamadı: " + err.Error())
	}
	if err := os.WriteFile(base+".html", []byte(html), 0o644); err != nil {
		return nil, networkError("Dev çıkış kutusu yazılamadı: " + err.Error())
	}
	fmt.Fprintf(devOutput, "[nafru] dev: e-posta gönderilmedi\n  %s.txt\n  %s.html\n\n%s", base, base, text)
	return &SendEmailResponse{ID: id}, nil
}
