package nafruemail

import "encoding/json"

// Ptr, isteğe bağlı alanlar için değerin işaretçisini verir: nafru.Ptr(true), nafru.Ptr(0).
func Ptr[T any](value T) *T { return &value }

// Nullable, güncelleme girdilerinde alanı temizlemek (JSON null) ile hiç göndermemeyi (nil) ayırır.
// nafru.Value("x") değer yazar, nafru.Null[string]() alanı null yapar.
type Nullable[T any] struct {
	value T
	null  bool
}

// Value, alanı verilen değere ayarlar.
func Value[T any](value T) *Nullable[T] { return &Nullable[T]{value: value} }

// Null, alanı açıkça null gönderir (temizler).
func Null[T any]() *Nullable[T] { return &Nullable[T]{null: true} }

func (n Nullable[T]) MarshalJSON() ([]byte, error) {
	if n.null {
		return []byte("null"), nil
	}
	return json.Marshal(n.value)
}

// ---- Ortak ----

// ListResponse, sunucunun { object: "list", data, has_more } liste zarfıdır.
type ListResponse[T any] struct {
	Object  string `json:"object"`
	Data    []T    `json:"data"`
	HasMore bool   `json:"has_more"`
	// lastID, Paginate'in after imleci: son öğenin id'si (ham JSON'dan okunur, öğe tipinden bağımsız).
	lastID string
}

type listPage[T any] struct {
	Object  string `json:"object"`
	Data    []T    `json:"data"`
	HasMore bool   `json:"has_more"`
}

type listIDs struct {
	Data []struct {
		ID string `json:"id"`
	} `json:"data"`
}

func (l *ListResponse[T]) UnmarshalJSON(data []byte) error {
	var page listPage[T]
	if err := json.Unmarshal(data, &page); err != nil {
		return err
	}
	var ids listIDs
	_ = json.Unmarshal(data, &ids)
	*l = ListResponse[T]{Object: page.Object, Data: page.Data, HasMore: page.HasMore}
	if n := len(ids.Data); n > 0 {
		l.lastID = ids.Data[n-1].ID
	}
	return nil
}

// ListQuery, imleçli liste sorgusudur: After ve Before birlikte verilemez.
type ListQuery struct {
	// Limit 1–100, varsayılan 20 (0: gönderilmez).
	Limit  int    `json:"limit,omitempty"`
	After  string `json:"after,omitempty"`
	Before string `json:"before,omitempty"`
}

type DeletedResponse struct {
	Object  string `json:"object"`
	ID      string `json:"id"`
	Deleted bool   `json:"deleted"`
}

type Tag struct {
	Name  string `json:"name"`
	Value string `json:"value"`
}

// ---- E-postalar ----

type Attachment struct {
	// Content Base64 metnidir; Path ile birlikte verilmez.
	Content string `json:"content,omitempty"`
	// Path herkese açık https adresidir; Content ile birlikte verilmez.
	Path        string `json:"path,omitempty"`
	Filename    string `json:"filename,omitempty"`
	ContentType string `json:"content_type,omitempty"`
	ContentID   string `json:"content_id,omitempty"`
}

// EmailTemplate, şablonla gönderimdir; değişken değerleri string ya da sayı.
type EmailTemplate struct {
	ID        string         `json:"id"`
	Variables map[string]any `json:"variables,omitempty"`
}

type SendEmailInput struct {
	// From "Ad <adres@alan.com>" ya da adres; şablonla gönderimde isteğe bağlı (çalışma alanı varsayılanı).
	From    string            `json:"from,omitempty"`
	To      []string          `json:"to"`
	Cc      []string          `json:"cc,omitempty"`
	Bcc     []string          `json:"bcc,omitempty"`
	ReplyTo []string          `json:"reply_to,omitempty"`
	Subject string            `json:"subject,omitempty"`
	Headers map[string]string `json:"headers,omitempty"`
	Tags    []Tag             `json:"tags,omitempty"`
	// ScheduledAt ISO 8601 ya da göreli ifade ("in 1 hour"); en fazla 30 gün sonrası.
	ScheduledAt string       `json:"scheduled_at,omitempty"`
	HTML        string       `json:"html,omitempty"`
	Text        string       `json:"text,omitempty"`
	Attachments []Attachment `json:"attachments,omitempty"`
	// Template HTML/Text/Attachments ile birlikte verilmez.
	Template *EmailTemplate `json:"template,omitempty"`
}

// BatchEmailItem, toplu öğedir: ek ve şablon desteklenmez.
type BatchEmailItem struct {
	From        string            `json:"from"`
	To          []string          `json:"to"`
	Cc          []string          `json:"cc,omitempty"`
	Bcc         []string          `json:"bcc,omitempty"`
	ReplyTo     []string          `json:"reply_to,omitempty"`
	Subject     string            `json:"subject"`
	Headers     map[string]string `json:"headers,omitempty"`
	Tags        []Tag             `json:"tags,omitempty"`
	ScheduledAt string            `json:"scheduled_at,omitempty"`
	HTML        string            `json:"html,omitempty"`
	Text        string            `json:"text,omitempty"`
}

// SendEmailOptions: IdempotencyKey ile yinelenen istek aynı e-postayı döndürür.
type SendEmailOptions struct {
	IdempotencyKey string
}

type SendEmailResponse struct {
	ID string `json:"id"`
}

type BatchEmailResponse struct {
	Data []SendEmailResponse `json:"data"`
}

type EmailListItem struct {
	ID          string   `json:"id"`
	To          []string `json:"to"`
	From        string   `json:"from"`
	CreatedAt   string   `json:"created_at"`
	Subject     string   `json:"subject"`
	Bcc         []string `json:"bcc"`
	Cc          []string `json:"cc"`
	ReplyTo     []string `json:"reply_to"`
	LastEvent   string   `json:"last_event"`
	ScheduledAt *string  `json:"scheduled_at"`
	MessageID   *string  `json:"message_id"`
}

type EmailEvent struct {
	ID        string         `json:"id"`
	Type      string         `json:"type"`
	CreatedAt string         `json:"created_at"`
	Detail    map[string]any `json:"detail"`
}

type Email struct {
	EmailListItem
	Object string       `json:"object"`
	HTML   *string      `json:"html"`
	Text   *string      `json:"text"`
	Tags   []Tag        `json:"tags"`
	Events []EmailEvent `json:"events"`
}

type ListEmailsQuery struct {
	ListQuery
	Status string `json:"status,omitempty"`
}

type UpdateEmailInput struct {
	ScheduledAt string `json:"scheduled_at"`
}

type EmailRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

// ---- Alan adları ----

type DomainRecord struct {
	Record   string `json:"record"`
	Name     string `json:"name"`
	Type     string `json:"type"`
	Value    string `json:"value"`
	TTL      string `json:"ttl"`
	Status   string `json:"status"`
	Priority *int   `json:"priority,omitempty"`
}

type DomainCapabilities struct {
	Sending   string `json:"sending"`
	Receiving string `json:"receiving"`
}

type Domain struct {
	ID                string             `json:"id"`
	Name              string             `json:"name"`
	Status            string             `json:"status"`
	CreatedAt         string             `json:"created_at"`
	Region            string             `json:"region"`
	Capabilities      DomainCapabilities `json:"capabilities"`
	OpenTracking      bool               `json:"open_tracking"`
	ClickTracking     bool               `json:"click_tracking"`
	TLS               string             `json:"tls"`
	TrackingSubdomain *string            `json:"tracking_subdomain"`
}

type DomainDetail struct {
	Domain
	Object  string         `json:"object"`
	Records []DomainRecord `json:"records"`
}

type CreateDomainInput struct {
	Name          string `json:"name"`
	Region        string `json:"region,omitempty"`
	OpenTracking  *bool  `json:"open_tracking,omitempty"`
	ClickTracking *bool  `json:"click_tracking,omitempty"`
	TLS           string `json:"tls,omitempty"`
	// TrackingSubdomain örn. "track" → track.<alan-adı>.
	TrackingSubdomain string `json:"tracking_subdomain,omitempty"`
}

type UpdateDomainInput struct {
	OpenTracking      *bool             `json:"open_tracking,omitempty"`
	ClickTracking     *bool             `json:"click_tracking,omitempty"`
	TLS               string            `json:"tls,omitempty"`
	TrackingSubdomain *Nullable[string] `json:"tracking_subdomain,omitempty"`
}

type DomainRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

// ---- Kişiler ----

type Contact struct {
	ID           string  `json:"id"`
	Email        string  `json:"email"`
	FirstName    *string `json:"first_name"`
	LastName     *string `json:"last_name"`
	Unsubscribed bool    `json:"unsubscribed"`
	Locale       *string `json:"locale"`
	CreatedAt    string  `json:"created_at"`
}

// ContactPropertyValue: Type "string" ise Value string, "number" ise float64.
type ContactPropertyValue struct {
	Type  string `json:"type"`
	Value any    `json:"value"`
}

type ContactDetail struct {
	Contact
	Object string `json:"object"`
	// Properties yalnız değeri olan alanlardır.
	Properties map[string]ContactPropertyValue `json:"properties"`
}

type ContactSegmentInput struct {
	ID string `json:"id"`
}

// ContactTopicInput: Subscription "opt_in" ya da "opt_out".
type ContactTopicInput struct {
	ID           string `json:"id"`
	Subscription string `json:"subscription"`
}

type CreateContactInput struct {
	Email        string `json:"email"`
	FirstName    string `json:"first_name,omitempty"`
	LastName     string `json:"last_name,omitempty"`
	Unsubscribed *bool  `json:"unsubscribed,omitempty"`
	// Locale ISO 639-1 ana dil kodu; bölgeli kod (pt-BR) sunucuda ana dile indirgenir.
	Locale string `json:"locale,omitempty"`
	// Properties değerleri string, sayı ya da nil.
	Properties map[string]any        `json:"properties,omitempty"`
	Segments   []ContactSegmentInput `json:"segments,omitempty"`
	Topics     []ContactTopicInput   `json:"topics,omitempty"`
}

type UpdateContactInput struct {
	FirstName    *Nullable[string] `json:"first_name,omitempty"`
	LastName     *Nullable[string] `json:"last_name,omitempty"`
	Unsubscribed *bool             `json:"unsubscribed,omitempty"`
	Locale       *Nullable[string] `json:"locale,omitempty"`
	Properties   map[string]any    `json:"properties,omitempty"`
}

type ListContactsQuery struct {
	ListQuery
	// Search e-posta, ad ya da soyad içinde arar.
	Search string `json:"search,omitempty"`
}

type ContactRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

type DeletedContact struct {
	Object  string `json:"object"`
	Contact string `json:"contact"`
	Deleted bool   `json:"deleted"`
}

// ContactSegmentRef, contacts.segments.add ({id}) ve remove ({id, deleted}) yanıtıdır.
type ContactSegmentRef struct {
	ID      string `json:"id"`
	Deleted bool   `json:"deleted,omitempty"`
}

type ContactProperty struct {
	ID            string `json:"id"`
	Key           string `json:"key"`
	Type          string `json:"type"`
	FallbackValue any    `json:"fallback_value"`
	CreatedAt     string `json:"created_at"`
}

type ContactPropertyDetail struct {
	ContactProperty
	Object string `json:"object"`
}

type CreateContactPropertyInput struct {
	Key string `json:"key"`
	// Type "string" ya da "number".
	Type          string `json:"type"`
	FallbackValue any    `json:"fallback_value,omitempty"`
}

type UpdateContactPropertyInput struct {
	FallbackValue *Nullable[any] `json:"fallback_value,omitempty"`
}

type ContactPropertyRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

// ---- Segmentler ----

type Segment struct {
	ID        string         `json:"id"`
	Name      string         `json:"name"`
	CreatedAt string         `json:"created_at"`
	Type      string         `json:"type"`
	Filter    map[string]any `json:"filter"`
}

type SegmentDetail struct {
	Segment
	Object string `json:"object"`
}

type CreateSegmentInput struct {
	Name string `json:"name"`
	// Filter verilirse dinamik segment.
	Filter map[string]any `json:"filter,omitempty"`
}

type SegmentRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
	Name   string `json:"name"`
}

// ---- Konular ----

type Topic struct {
	ID                  string  `json:"id"`
	Name                string  `json:"name"`
	Description         *string `json:"description"`
	DefaultSubscription string  `json:"default_subscription"`
	Visibility          string  `json:"visibility"`
	DoubleOptIn         bool    `json:"double_opt_in"`
	CreatedAt           string  `json:"created_at"`
}

type TopicDetail struct {
	Topic
	Object string `json:"object"`
}

type CreateTopicInput struct {
	Name                string `json:"name"`
	DefaultSubscription string `json:"default_subscription"`
	Description         string `json:"description,omitempty"`
	Visibility          string `json:"visibility,omitempty"`
	DoubleOptIn         *bool  `json:"double_opt_in,omitempty"`
}

type UpdateTopicInput struct {
	Name        string            `json:"name,omitempty"`
	Description *Nullable[string] `json:"description,omitempty"`
	Visibility  string            `json:"visibility,omitempty"`
	DoubleOptIn *bool             `json:"double_opt_in,omitempty"`
}

type TopicRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

type ContactTopic struct {
	ID           string  `json:"id"`
	Name         string  `json:"name"`
	Description  *string `json:"description"`
	Subscription string  `json:"subscription"`
	// Status "pending": çift onay bekliyor (Subscription bu durumda opt_out görünür).
	Status string `json:"status"`
}

type UpdateContactTopicsInput struct {
	Topics []ContactTopicInput
}

// ---- Kampanyalar ----

type BroadcastListItem struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	SegmentID   string  `json:"segment_id"`
	AudienceID  string  `json:"audience_id"`
	Subject     string  `json:"subject"`
	Status      string  `json:"status"`
	CreatedAt   string  `json:"created_at"`
	ScheduledAt *string `json:"scheduled_at"`
	SentAt      *string `json:"sent_at"`
	// Recurrence tekrar kuralı (şablon kaydında); yoksa nil.
	Recurrence *BroadcastRecurrence `json:"recurrence"`
	// TriggerState şablonun tetik durumu: active, paused; nil = başlatılmadı.
	TriggerState *string `json:"trigger_state"`
	// NextRunAt sonraki zamanlı çalışma (ISO 8601).
	NextRunAt *string `json:"next_run_at"`
	// ParentID çalışma örneğinde şablonun kimliği.
	ParentID *string `json:"parent_id"`
}

// Tekrar kuralı türleri.
const (
	RecurrenceWeekly   = "weekly"
	RecurrenceMonthly  = "monthly"
	RecurrenceInterval = "interval"
)

// BroadcastRecurrence, Type'a göre ayrışan tekrar kuralıdır; yalnız o türün alanları doldurulur (bilinmeyen tür de çözülür).
// Time (HH:MM) çalışma alanının saat dilimindedir.
//
//	weekly:   Days (0 = pazar … 6 = cumartesi), Time
//	monthly:  Day (1–31; ay kısaysa son gün), Time
//	interval: EveryDays (1–365), Time
type BroadcastRecurrence struct {
	Type      string `json:"type"`
	Days      []int  `json:"days,omitempty"`
	Day       int    `json:"day,omitempty"`
	EveryDays int    `json:"every_days,omitempty"`
	Time      string `json:"time"`
}

// Veri kaynağı türleri.
const (
	DataSourceManual  = "manual"
	DataSourceURL     = "url"
	DataSourceWebhook = "webhook"
)

// BroadcastDataSourceInput, {{{data.*}}} değişkenlerinin kaynağıdır; Type'a göre:
//
//	manual:  alan yok
//	url:     URL, HeaderName, HeaderValue (gönderim anında GET; https, ≤ 256 KB JSON nesne, 10 sn)
//	webhook: RegenerateSecret (imzalı tetik ucu)
type BroadcastDataSourceInput struct {
	Type             string            `json:"type"`
	URL              string            `json:"url,omitempty"`
	HeaderName       *Nullable[string] `json:"header_name,omitempty"`
	HeaderValue      *Nullable[string] `json:"header_value,omitempty"`
	RegenerateSecret *bool             `json:"regenerate_secret,omitempty"`
}

// BroadcastDataSource, yanıttaki veri kaynağıdır; Type'a göre yalnız o türün alanları doludur:
// url: URL, HeaderName, HasHeaderValue; webhook: TriggerURL, Secret.
type BroadcastDataSource struct {
	Type           string  `json:"type"`
	URL            string  `json:"url,omitempty"`
	HeaderName     *string `json:"header_name,omitempty"`
	HasHeaderValue bool    `json:"has_header_value,omitempty"`
	TriggerURL     string  `json:"trigger_url,omitempty"`
	Secret         string  `json:"secret,omitempty"`
}

type Broadcast struct {
	BroadcastListItem
	Object        string   `json:"object"`
	From          string   `json:"from"`
	ReplyTo       []string `json:"reply_to"`
	PreviewText   *string  `json:"preview_text"`
	TopicID       *string  `json:"topic_id"`
	TemplateID    *string  `json:"template_id"`
	HTML          *string  `json:"html"`
	Text          *string  `json:"text"`
	OpenTracking  bool     `json:"open_tracking"`
	ClickTracking bool     `json:"click_tracking"`
	FinishedAt    *string  `json:"finished_at"`
	FailureReason *string  `json:"failure_reason"`
	// Data şablondaki {{{data.*}}} bağlamı (gönderilmiş örnekte gönderim anında çözülen değer).
	Data       map[string]any       `json:"data"`
	DataSource *BroadcastDataSource `json:"data_source"`
}

type CreateBroadcastInput struct {
	// Name boşsa konu satırı.
	Name      string   `json:"name,omitempty"`
	SegmentID string   `json:"segment_id"`
	TopicID   string   `json:"topic_id,omitempty"`
	From      string   `json:"from"`
	Subject   string   `json:"subject,omitempty"`
	ReplyTo   []string `json:"reply_to,omitempty"`
	HTML      string   `json:"html,omitempty"`
	Text      string   `json:"text,omitempty"`
	// TemplateID şablon kimliği ya da takma adı; HTML/Text ile birlikte verilmez.
	TemplateID  string `json:"template_id,omitempty"`
	PreviewText string `json:"preview_text,omitempty"`
	// Send true: aynı istekte gönderir. ScheduledAt yalnız bununla anlamlıdır.
	Send          *bool  `json:"send,omitempty"`
	ScheduledAt   string `json:"scheduled_at,omitempty"`
	OpenTracking  *bool  `json:"open_tracking,omitempty"`
	ClickTracking *bool  `json:"click_tracking,omitempty"`
	// Data {{{data.*}}} değişkenlerinin değeri (JSON nesne, ≤ 256 KB).
	Data       map[string]any            `json:"data,omitempty"`
	DataSource *BroadcastDataSourceInput `json:"data_source,omitempty"`
	// Recurrence verilirse kayıt tekrarlayan bir şablondur: Send onu başlatmaz, etkinleştirir; her çalışma yeni bir toplu gönderim oluşturur.
	Recurrence *BroadcastRecurrence `json:"recurrence,omitempty"`
}

type UpdateBroadcastInput struct {
	Name          string                              `json:"name,omitempty"`
	SegmentID     string                              `json:"segment_id,omitempty"`
	TopicID       *Nullable[string]                   `json:"topic_id,omitempty"`
	From          string                              `json:"from,omitempty"`
	Subject       string                              `json:"subject,omitempty"`
	ReplyTo       []string                            `json:"reply_to,omitempty"`
	HTML          string                              `json:"html,omitempty"`
	Text          string                              `json:"text,omitempty"`
	PreviewText   *Nullable[string]                   `json:"preview_text,omitempty"`
	OpenTracking  *bool                               `json:"open_tracking,omitempty"`
	ClickTracking *bool                               `json:"click_tracking,omitempty"`
	Data          *Nullable[map[string]any]           `json:"data,omitempty"`
	DataSource    *Nullable[BroadcastDataSourceInput] `json:"data_source,omitempty"`
	Recurrence    *Nullable[BroadcastRecurrence]      `json:"recurrence,omitempty"`
}

type SendBroadcastInput struct {
	ScheduledAt string `json:"scheduled_at,omitempty"`
	// Data bu gönderimin {{{data.*}}} bağlamı (taslaktakinin yerine).
	Data map[string]any `json:"data,omitempty"`
}

type BroadcastRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

// ---- Marka ----

type BrandSocialLink struct {
	// Network: website, x, facebook, instagram, linkedin, youtube, github, tiktok.
	Network string `json:"network"`
	URL     string `json:"url"`
}

// Brand, çalışma alanının markasıdır. Ayarlanmamış renk/yazı tipi/genişlik varsayılanla döner; Configured marka hiç kaydedilmediyse false.
type Brand struct {
	Object           string            `json:"object"`
	Configured       bool              `json:"configured"`
	LogoAssetID      *string           `json:"logo_asset_id"`
	LogoURL          *string           `json:"logo_url"`
	LogoDarkAssetID  *string           `json:"logo_dark_asset_id"`
	LogoDarkURL      *string           `json:"logo_dark_url"`
	LogoWidth        int               `json:"logo_width"`
	LogoAlign        string            `json:"logo_align"`
	HeaderEnabled    bool              `json:"header_enabled"`
	AccentColor      string            `json:"accent_color"`
	TextColor        string            `json:"text_color"`
	BackdropColor    string            `json:"backdrop_color"`
	CanvasColor      string            `json:"canvas_color"`
	LinkColor        string            `json:"link_color"`
	FontFamily       string            `json:"font_family"`
	ButtonStyle      string            `json:"button_style"`
	ContentWidth     int               `json:"content_width"`
	FooterText       *string           `json:"footer_text"`
	LegalText        *string           `json:"legal_text"`
	PostalAddress    *string           `json:"postal_address"`
	WebsiteURL       *string           `json:"website_url"`
	SocialLinks      []BrandSocialLink `json:"social_links"`
	UnsubscribeLabel string            `json:"unsubscribe_label"`
	UpdatedAt        *string           `json:"updated_at"`
}

// UpdateBrandInput markanın TAMAMINI değiştirir: gönderilmeyen alan "ayarlanmadı" olur. Önce Brand.Get ile okuyup değiştirin.
type UpdateBrandInput struct {
	LogoAssetID      string            `json:"logo_asset_id,omitempty"`
	LogoDarkAssetID  string            `json:"logo_dark_asset_id,omitempty"`
	LogoWidth        *int              `json:"logo_width,omitempty"`
	LogoAlign        string            `json:"logo_align,omitempty"`
	HeaderEnabled    *bool             `json:"header_enabled,omitempty"`
	AccentColor      string            `json:"accent_color,omitempty"`
	TextColor        string            `json:"text_color,omitempty"`
	BackdropColor    string            `json:"backdrop_color,omitempty"`
	CanvasColor      string            `json:"canvas_color,omitempty"`
	LinkColor        string            `json:"link_color,omitempty"`
	FontFamily       string            `json:"font_family,omitempty"`
	ButtonStyle      string            `json:"button_style,omitempty"`
	ContentWidth     *int              `json:"content_width,omitempty"`
	FooterText       string            `json:"footer_text,omitempty"`
	LegalText        string            `json:"legal_text,omitempty"`
	PostalAddress    string            `json:"postal_address,omitempty"`
	WebsiteURL       string            `json:"website_url,omitempty"`
	SocialLinks      []BrandSocialLink `json:"social_links,omitempty"`
	UnsubscribeLabel string            `json:"unsubscribe_label,omitempty"`
}

// TemplateBrandOverride, şablon başına markayı ezen alanlardır (yalnız custom kipte).
type TemplateBrandOverride struct {
	AccentColor   string `json:"accent_color,omitempty"`
	TextColor     string `json:"text_color,omitempty"`
	BackdropColor string `json:"backdrop_color,omitempty"`
	CanvasColor   string `json:"canvas_color,omitempty"`
	FontFamily    string `json:"font_family,omitempty"`
	LinkColor     string `json:"link_color,omitempty"`
	ContentWidth  *int   `json:"content_width,omitempty"`
	ShowHeader    *bool  `json:"show_header,omitempty"`
	ShowFooter    *bool  `json:"show_footer,omitempty"`
}

// TemplateBrand: Mode inherit (marka olduğu gibi), custom (marka + Override), none (hiçbir şey eklenmez).
type TemplateBrand struct {
	Mode     string                 `json:"mode"`
	Override *TemplateBrandOverride `json:"override,omitempty"`
}

// ---- Şablonlar ----

type TemplateListItem struct {
	ID                    string  `json:"id"`
	Name                  string  `json:"name"`
	Alias                 *string `json:"alias"`
	Type                  string  `json:"type"`
	Status                string  `json:"status"`
	Subject               *string `json:"subject"`
	CurrentVersion        *int    `json:"current_version"`
	HasUnpublishedChanges bool    `json:"has_unpublished_changes"`
	PublishedAt           *string `json:"published_at"`
	CreatedAt             string  `json:"created_at"`
	UpdatedAt             string  `json:"updated_at"`
}

// TemplateVariable: şablonda {{{AD}}} ya da {{{AD|yedek}}}.
type TemplateVariable struct {
	Key           string  `json:"key"`
	Type          string  `json:"type"`
	FallbackValue *string `json:"fallback_value"`
}

type Template struct {
	TemplateListItem
	Object      string             `json:"object"`
	PreviewText *string            `json:"preview_text"`
	HTML        string             `json:"html"`
	Text        *string            `json:"text"`
	Design      json.RawMessage    `json:"design"`
	Revision    int                `json:"revision"`
	Variables   []TemplateVariable `json:"variables"`
	Brand       TemplateBrand      `json:"brand"`
}

type CreateTemplateInput struct {
	Name        string `json:"name"`
	Alias       string `json:"alias,omitempty"`
	Subject     string `json:"subject,omitempty"`
	PreviewText string `json:"preview_text,omitempty"`
	HTML        string `json:"html"`
	Text        string `json:"text,omitempty"`
	// Brand verilmezse { mode: "none" }: HTML olduğu gibi kalır.
	Brand *TemplateBrand `json:"brand,omitempty"`
}

type UpdateTemplateInput struct {
	// Revision eşzamanlı düzenleme denetimi: önceki okumadaki revision.
	Revision    *int              `json:"revision,omitempty"`
	Name        string            `json:"name,omitempty"`
	Alias       *Nullable[string] `json:"alias,omitempty"`
	Subject     *Nullable[string] `json:"subject,omitempty"`
	PreviewText *Nullable[string] `json:"preview_text,omitempty"`
	HTML        string            `json:"html,omitempty"`
	Text        *Nullable[string] `json:"text,omitempty"`
	Brand       *TemplateBrand    `json:"brand,omitempty"`
}

type TemplateRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

type TemplateSaved struct {
	TemplateRef
	Revision int `json:"revision"`
}

type TemplatePublished struct {
	TemplateRef
	Version   int    `json:"version"`
	VersionID string `json:"version_id"`
	Revision  int    `json:"revision"`
}

// PutTemplateTranslationInput, bir dilin taslağıdır; API anahtarıyla yalnız html türü şablonda.
type PutTemplateTranslationInput struct {
	Subject     string `json:"subject,omitempty"`
	PreviewText string `json:"preview_text,omitempty"`
	HTML        string `json:"html"`
	Text        string `json:"text,omitempty"`
}

type TemplateTranslation struct {
	Locale         string  `json:"locale"`
	Subject        *string `json:"subject"`
	PreviewText    *string `json:"preview_text"`
	DesignRevision int     `json:"design_revision"`
	UpdatedAt      string  `json:"updated_at"`
}

type TemplateTranslationDeleted struct {
	Object  string `json:"object"`
	Locale  string `json:"locale"`
	Deleted bool   `json:"deleted"`
}

// ---- Webhook'lar ----

type Webhook struct {
	ID        string   `json:"id"`
	Endpoint  string   `json:"endpoint"`
	CreatedAt string   `json:"created_at"`
	Status    string   `json:"status"`
	Events    []string `json:"events"`
}

type WebhookDetail struct {
	Webhook
	Object        string `json:"object"`
	SigningSecret string `json:"signing_secret"`
}

type CreateWebhookInput struct {
	Endpoint string `json:"endpoint"`
	// Events örn. email.sent, email.delivered, contact.created.
	Events []string `json:"events"`
}

type CreatedWebhook struct {
	Object string `json:"object"`
	ID     string `json:"id"`
	// SigningSecret yalnız bu yanıtta ve ayrıntıda görünür; VerifyWebhook bununla doğrular.
	SigningSecret string `json:"signing_secret"`
}

type UpdateWebhookInput struct {
	Endpoint string   `json:"endpoint,omitempty"`
	Events   []string `json:"events,omitempty"`
	Status   string   `json:"status,omitempty"`
}

type WebhookRef struct {
	Object string `json:"object"`
	ID     string `json:"id"`
}

// WebhookPayload, webhook gövdesidir: { type, created_at, data }.
type WebhookPayload struct {
	Type      string          `json:"type"`
	CreatedAt string          `json:"created_at"`
	Data      json.RawMessage `json:"data"`
}

// ---- API anahtarları ----

type APIKey struct {
	ID          string  `json:"id"`
	Name        string  `json:"name"`
	CreatedAt   string  `json:"created_at"`
	LastUsedAt  *string `json:"last_used_at"`
	Permission  string  `json:"permission"`
	DomainID    *string `json:"domain_id"`
	TokenPrefix string  `json:"token_prefix"`
}

type CreateAPIKeyInput struct {
	Name string `json:"name"`
	// Permission full_access (varsayılan) ya da sending_access.
	Permission string `json:"permission,omitempty"`
	// DomainID yalnız sending_access ile: anahtarı bu alan adına kısıtlar.
	DomainID string `json:"domain_id,omitempty"`
}

type CreatedAPIKey struct {
	ID string `json:"id"`
	// Token tam anahtardır; yalnız bir kez görünür.
	Token string `json:"token"`
}

// ---- Olaylar ----

// EventContact: Email ya da ID'den biri. E-posta ile verilen kişi yoksa oluşturulur; kimlikle verilen yoksa 404.
type EventContact struct {
	Email string `json:"email,omitempty"`
	ID    string `json:"id,omitempty"`
}

type SendEventInput struct {
	// Name ^[a-z0-9_.:-]{1,64}$; email., contact., segment., topic., automation. ön ekleri ayrılmıştır.
	Name    string       `json:"name"`
	Contact EventContact `json:"contact"`
	// Properties değerleri string, sayı, bool ya da nil.
	Properties map[string]any `json:"properties,omitempty"`
	OccurredAt string         `json:"occurred_at,omitempty"`
	// Unsubscribed yalnız kişi bu istekle oluşturuluyorsa.
	Unsubscribed *bool `json:"unsubscribed,omitempty"`
}

type SendEventOptions struct {
	IdempotencyKey string
}

type EventAccepted struct {
	ID string `json:"id"`
}

type EventBatchResponse struct {
	Data []EventAccepted `json:"data"`
}

type EventItem struct {
	ID         string         `json:"id"`
	Name       string         `json:"name"`
	ContactID  string         `json:"contact_id"`
	Email      string         `json:"email"`
	Properties map[string]any `json:"properties"`
	Source     string         `json:"source"`
	OccurredAt string         `json:"occurred_at"`
	CreatedAt  string         `json:"created_at"`
}

type ListEventsQuery struct {
	ListQuery
	Name      string `json:"name,omitempty"`
	ContactID string `json:"contact_id,omitempty"`
	// Email ContactID ile birlikte verilmez.
	Email string `json:"email,omitempty"`
}

// ---- Nafru ile bağlan ----

// Uygulamanın müşteriden isteyebileceği izinler.
const (
	ScopeEmailsSend     = "emails.send"
	ScopeEmailsRead     = "emails.read"
	ScopeTemplatesRead  = "templates.read"
	ScopeDomainsRead    = "domains.read"
	ScopeSendersRead    = "senders.read"
	ScopeConnectionRead = "connection.read"
)

type AuthorizeURLInput struct {
	// RedirectURI kayıtlı yönlendirme adresiyle birebir aynı olmalı.
	RedirectURI string
	// State CSRF koruması: istekten önce üretip oturumda saklayın, dönüşte karşılaştırın. Zorunlu.
	State  string
	Scopes []string
	// LoginHint müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir.
	LoginHint string
}

type AuthorizeURL struct {
	URL string
	// CodeVerifier yalnız bu bağlanma denemesi için; Exchange çağrısına kadar sunucunuzda (oturumda) saklayın.
	CodeVerifier string
}

type ExchangeInput struct {
	Code         string
	CodeVerifier string
	RedirectURI  string
}

type ConnectionGrant struct {
	// ConnectionID conn_…: müşteri bağlantısının kalıcı kimliği.
	ConnectionID string
	// RefreshToken şifreleyerek saklayın; her yenilemede değişir (OnTokenRefresh).
	RefreshToken string
	Scopes       []string
}

type ConnectionTokens struct {
	RefreshToken string
}

type ConnectionStatus struct {
	Object string `json:"object"`
	ID     string `json:"id"`
	Ready  bool   `json:"ready"`
	// Missing hazır olmak için müşterinin tamamlaması gerekenler: domain, sender, plan.
	Missing     []string `json:"missing"`
	Hints       []string `json:"hints"`
	Scopes      []string `json:"scopes"`
	BillingMode string   `json:"billing_mode"`
	SetupURL    string   `json:"setup_url"`
	Workspace   struct {
		Name string `json:"name"`
	} `json:"workspace"`
}

type ConnectionSenderDomain struct {
	ID   string `json:"id"`
	Name string `json:"name"`
}

type ConnectionSenders struct {
	Domains     []ConnectionSenderDomain `json:"domains"`
	DefaultFrom *string                  `json:"default_from"`
}

type ConnectionTemplate struct {
	Key                string `json:"key"`
	Name               string `json:"name"`
	Source             string `json:"source"`
	CustomizedFromPack bool   `json:"customized_from_pack"`
}
