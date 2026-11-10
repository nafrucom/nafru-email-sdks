package nafruemail

import (
	"context"
	"net/http"
)

// call, istekleri gönderip T'ye çözer.
func call[T any](ctx context.Context, c caller, in requestInput) (*T, error) {
	var out T
	if err := c(ctx, in, &out); err != nil {
		return nil, err
	}
	return &out, nil
}

func get[T any](ctx context.Context, c caller, path string, query any) (*T, error) {
	return call[T](ctx, c, requestInput{method: http.MethodGet, path: path, query: query})
}

func send[T any](ctx context.Context, c caller, method, path string, body any) (*T, error) {
	return call[T](ctx, c, requestInput{method: method, path: path, body: body})
}

func idempotencyKey(options []SendEmailOptions) string {
	if len(options) > 0 {
		return options[0].IdempotencyKey
	}
	return ""
}

// ---- E-postalar ----

type EmailsResource struct {
	call      caller
	devOutbox string
}

// Send: POST /emails. ScheduledAt verilirse zamanlanır; IdempotencyKey ile yineleme güvenlidir.
func (r *EmailsResource) Send(ctx context.Context, input *SendEmailInput, options ...SendEmailOptions) (*SendEmailResponse, error) {
	if r.devOutbox != "" {
		return writeDevEmail(r.devOutbox, devEmailFromSend(input))
	}
	return call[SendEmailResponse](ctx, r.call, requestInput{
		method: http.MethodPost, path: "/emails", body: input, idempotencyKey: idempotencyKey(options),
	})
}

// Batch: POST /emails/batch, en çok 100 e-posta; ek ve şablon desteklenmez.
func (r *EmailsResource) Batch(ctx context.Context, input []BatchEmailItem, options ...SendEmailOptions) (*BatchEmailResponse, error) {
	if r.devOutbox == "" {
		return call[BatchEmailResponse](ctx, r.call, requestInput{
			method: http.MethodPost, path: "/emails/batch", body: input, idempotencyKey: idempotencyKey(options),
		})
	}
	out := &BatchEmailResponse{Data: []SendEmailResponse{}}
	for i := range input {
		sent, err := writeDevEmail(r.devOutbox, devEmailFromBatch(&input[i]))
		if err != nil {
			return nil, err
		}
		out.Data = append(out.Data, *sent)
	}
	return out, nil
}

func (r *EmailsResource) Get(ctx context.Context, id string) (*Email, error) {
	return get[Email](ctx, r.call, "/emails/"+seg(id), nil)
}

func (r *EmailsResource) List(ctx context.Context, query *ListEmailsQuery) (*ListResponse[EmailListItem], error) {
	return get[ListResponse[EmailListItem]](ctx, r.call, "/emails", query)
}

// Update, zamanlanmış e-postanın gönderim anını değiştirir.
func (r *EmailsResource) Update(ctx context.Context, id string, input *UpdateEmailInput) (*EmailRef, error) {
	return send[EmailRef](ctx, r.call, http.MethodPatch, "/emails/"+seg(id), input)
}

// Cancel, zamanlanmış e-postayı iptal eder.
func (r *EmailsResource) Cancel(ctx context.Context, id string) (*EmailRef, error) {
	return send[EmailRef](ctx, r.call, http.MethodPost, "/emails/"+seg(id)+"/cancel", nil)
}

// ---- Alan adları ----

type DomainsResource struct{ call caller }

func (r *DomainsResource) Create(ctx context.Context, input *CreateDomainInput) (*DomainDetail, error) {
	return send[DomainDetail](ctx, r.call, http.MethodPost, "/domains", input)
}

func (r *DomainsResource) Get(ctx context.Context, id string) (*DomainDetail, error) {
	return get[DomainDetail](ctx, r.call, "/domains/"+seg(id), nil)
}

func (r *DomainsResource) List(ctx context.Context, query *ListQuery) (*ListResponse[Domain], error) {
	return get[ListResponse[Domain]](ctx, r.call, "/domains", query)
}

func (r *DomainsResource) Update(ctx context.Context, id string, input *UpdateDomainInput) (*DomainRef, error) {
	return send[DomainRef](ctx, r.call, http.MethodPatch, "/domains/"+seg(id), input)
}

func (r *DomainsResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/domains/"+seg(id), nil)
}

// Verify, DNS kayıtlarını denetletir; sonuç Get ile okunur.
func (r *DomainsResource) Verify(ctx context.Context, id string) (*DomainRef, error) {
	return send[DomainRef](ctx, r.call, http.MethodPost, "/domains/"+seg(id)+"/verify", nil)
}

// ---- Kişiler (id yerine e-posta adresi de verilebilir) ----

type ContactsResource struct {
	call     caller
	Segments *ContactSegmentsResource
	Topics   *ContactTopicsResource
}

func (r *ContactsResource) Create(ctx context.Context, input *CreateContactInput) (*ContactRef, error) {
	return send[ContactRef](ctx, r.call, http.MethodPost, "/contacts", input)
}

func (r *ContactsResource) Get(ctx context.Context, idOrEmail string) (*ContactDetail, error) {
	return get[ContactDetail](ctx, r.call, "/contacts/"+seg(idOrEmail), nil)
}

func (r *ContactsResource) List(ctx context.Context, query *ListContactsQuery) (*ListResponse[Contact], error) {
	return get[ListResponse[Contact]](ctx, r.call, "/contacts", query)
}

func (r *ContactsResource) Update(ctx context.Context, idOrEmail string, input *UpdateContactInput) (*ContactRef, error) {
	return send[ContactRef](ctx, r.call, http.MethodPatch, "/contacts/"+seg(idOrEmail), input)
}

func (r *ContactsResource) Remove(ctx context.Context, idOrEmail string) (*DeletedContact, error) {
	return send[DeletedContact](ctx, r.call, http.MethodDelete, "/contacts/"+seg(idOrEmail), nil)
}

type ContactSegmentsResource struct{ call caller }

func (r *ContactSegmentsResource) List(ctx context.Context, idOrEmail string, query *ListQuery) (*ListResponse[Segment], error) {
	return get[ListResponse[Segment]](ctx, r.call, "/contacts/"+seg(idOrEmail)+"/segments", query)
}

// Add, kişiyi statik segmente ekler (dinamik segmentte 422).
func (r *ContactSegmentsResource) Add(ctx context.Context, idOrEmail, segmentID string) (*ContactSegmentRef, error) {
	return send[ContactSegmentRef](ctx, r.call, http.MethodPost, "/contacts/"+seg(idOrEmail)+"/segments/"+seg(segmentID), nil)
}

func (r *ContactSegmentsResource) Remove(ctx context.Context, idOrEmail, segmentID string) (*ContactSegmentRef, error) {
	return send[ContactSegmentRef](ctx, r.call, http.MethodDelete, "/contacts/"+seg(idOrEmail)+"/segments/"+seg(segmentID), nil)
}

type ContactTopicsResource struct{ call caller }

func (r *ContactTopicsResource) List(ctx context.Context, idOrEmail string, query *ListQuery) (*ListResponse[ContactTopic], error) {
	return get[ListResponse[ContactTopic]](ctx, r.call, "/contacts/"+seg(idOrEmail)+"/topics", query)
}

func (r *ContactTopicsResource) Update(ctx context.Context, idOrEmail string, input *UpdateContactTopicsInput) (*ContactRef, error) {
	topics := []ContactTopicInput{}
	if input != nil && input.Topics != nil {
		topics = input.Topics
	}
	// Sunucu gövdede çıplak dizi bekler.
	return send[ContactRef](ctx, r.call, http.MethodPatch, "/contacts/"+seg(idOrEmail)+"/topics", topics)
}

type ContactPropertiesResource struct{ call caller }

func (r *ContactPropertiesResource) Create(ctx context.Context, input *CreateContactPropertyInput) (*ContactPropertyRef, error) {
	return send[ContactPropertyRef](ctx, r.call, http.MethodPost, "/contact-properties", input)
}

func (r *ContactPropertiesResource) Get(ctx context.Context, id string) (*ContactPropertyDetail, error) {
	return get[ContactPropertyDetail](ctx, r.call, "/contact-properties/"+seg(id), nil)
}

func (r *ContactPropertiesResource) List(ctx context.Context, query *ListQuery) (*ListResponse[ContactProperty], error) {
	return get[ListResponse[ContactProperty]](ctx, r.call, "/contact-properties", query)
}

func (r *ContactPropertiesResource) Update(ctx context.Context, id string, input *UpdateContactPropertyInput) (*ContactPropertyRef, error) {
	return send[ContactPropertyRef](ctx, r.call, http.MethodPatch, "/contact-properties/"+seg(id), input)
}

func (r *ContactPropertiesResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/contact-properties/"+seg(id), nil)
}

// ---- Segmentler ----

type SegmentsResource struct{ call caller }

func (r *SegmentsResource) Create(ctx context.Context, input *CreateSegmentInput) (*SegmentRef, error) {
	return send[SegmentRef](ctx, r.call, http.MethodPost, "/segments", input)
}

func (r *SegmentsResource) Get(ctx context.Context, id string) (*SegmentDetail, error) {
	return get[SegmentDetail](ctx, r.call, "/segments/"+seg(id), nil)
}

func (r *SegmentsResource) List(ctx context.Context, query *ListQuery) (*ListResponse[Segment], error) {
	return get[ListResponse[Segment]](ctx, r.call, "/segments", query)
}

func (r *SegmentsResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/segments/"+seg(id), nil)
}

// Contacts, segmentin kişileridir; sayfalama kimlik sırasıyla, yalnız Limit ve After.
func (r *SegmentsResource) Contacts(ctx context.Context, id string, query *ListQuery) (*ListResponse[Contact], error) {
	return get[ListResponse[Contact]](ctx, r.call, "/segments/"+seg(id)+"/contacts", query)
}

// ---- Konular ----

type TopicsResource struct{ call caller }

func (r *TopicsResource) Create(ctx context.Context, input *CreateTopicInput) (*TopicRef, error) {
	return send[TopicRef](ctx, r.call, http.MethodPost, "/topics", input)
}

func (r *TopicsResource) Get(ctx context.Context, id string) (*TopicDetail, error) {
	return get[TopicDetail](ctx, r.call, "/topics/"+seg(id), nil)
}

func (r *TopicsResource) List(ctx context.Context, query *ListQuery) (*ListResponse[Topic], error) {
	return get[ListResponse[Topic]](ctx, r.call, "/topics", query)
}

func (r *TopicsResource) Update(ctx context.Context, id string, input *UpdateTopicInput) (*TopicRef, error) {
	return send[TopicRef](ctx, r.call, http.MethodPatch, "/topics/"+seg(id), input)
}

func (r *TopicsResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/topics/"+seg(id), nil)
}

// ---- Kampanyalar ----

type BroadcastsResource struct{ call caller }

// Create taslak oluşturur; Send: true ile aynı istekte gönderir.
func (r *BroadcastsResource) Create(ctx context.Context, input *CreateBroadcastInput) (*BroadcastRef, error) {
	return send[BroadcastRef](ctx, r.call, http.MethodPost, "/broadcasts", input)
}

func (r *BroadcastsResource) Get(ctx context.Context, id string) (*Broadcast, error) {
	return get[Broadcast](ctx, r.call, "/broadcasts/"+seg(id), nil)
}

func (r *BroadcastsResource) List(ctx context.Context, query *ListQuery) (*ListResponse[BroadcastListItem], error) {
	return get[ListResponse[BroadcastListItem]](ctx, r.call, "/broadcasts", query)
}

// Update yalnız taslakta (aksi 409).
func (r *BroadcastsResource) Update(ctx context.Context, id string, input *UpdateBroadcastInput) (*BroadcastRef, error) {
	return send[BroadcastRef](ctx, r.call, http.MethodPatch, "/broadcasts/"+seg(id), input)
}

// Remove yalnız taslakta (aksi 409).
func (r *BroadcastsResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/broadcasts/"+seg(id), nil)
}

// Send kampanyayı gönderir; input nil olabilir (hemen gönderim).
func (r *BroadcastsResource) Send(ctx context.Context, id string, input *SendBroadcastInput) (*BroadcastRef, error) {
	if input == nil {
		input = &SendBroadcastInput{}
	}
	return send[BroadcastRef](ctx, r.call, http.MethodPost, "/broadcasts/"+seg(id)+"/send", input)
}

func (r *BroadcastsResource) Cancel(ctx context.Context, id string) (*BroadcastRef, error) {
	return send[BroadcastRef](ctx, r.call, http.MethodPost, "/broadcasts/"+seg(id)+"/cancel", nil)
}

// ---- Şablonlar (kimlik ya da takma ad) ----

type TemplatesResource struct{ call caller }

func (r *TemplatesResource) Create(ctx context.Context, input *CreateTemplateInput) (*TemplateSaved, error) {
	return send[TemplateSaved](ctx, r.call, http.MethodPost, "/templates", input)
}

func (r *TemplatesResource) Get(ctx context.Context, idOrAlias string) (*Template, error) {
	return get[Template](ctx, r.call, "/templates/"+seg(idOrAlias), nil)
}

func (r *TemplatesResource) List(ctx context.Context, query *ListQuery) (*ListResponse[TemplateListItem], error) {
	return get[ListResponse[TemplateListItem]](ctx, r.call, "/templates", query)
}

// Update taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.
func (r *TemplatesResource) Update(ctx context.Context, idOrAlias string, input *UpdateTemplateInput) (*TemplateSaved, error) {
	return send[TemplateSaved](ctx, r.call, http.MethodPatch, "/templates/"+seg(idOrAlias), input)
}

func (r *TemplatesResource) Remove(ctx context.Context, idOrAlias string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/templates/"+seg(idOrAlias), nil)
}

func (r *TemplatesResource) Publish(ctx context.Context, idOrAlias string) (*TemplatePublished, error) {
	return send[TemplatePublished](ctx, r.call, http.MethodPost, "/templates/"+seg(idOrAlias)+"/publish", nil)
}

func (r *TemplatesResource) Duplicate(ctx context.Context, idOrAlias string) (*TemplateRef, error) {
	return send[TemplateRef](ctx, r.call, http.MethodPost, "/templates/"+seg(idOrAlias)+"/duplicate", nil)
}

// PutTranslation dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.
func (r *TemplatesResource) PutTranslation(ctx context.Context, idOrAlias, locale string, input *PutTemplateTranslationInput) (*TemplateTranslation, error) {
	return send[TemplateTranslation](ctx, r.call, http.MethodPut, "/templates/"+seg(idOrAlias)+"/translations/"+seg(locale), input)
}

func (r *TemplatesResource) RemoveTranslation(ctx context.Context, idOrAlias, locale string) (*TemplateTranslationDeleted, error) {
	return send[TemplateTranslationDeleted](ctx, r.call, http.MethodDelete, "/templates/"+seg(idOrAlias)+"/translations/"+seg(locale), nil)
}

// ---- Marka ----

type BrandResource struct{ call caller }

func (r *BrandResource) Get(ctx context.Context) (*Brand, error) {
	return get[Brand](ctx, r.call, "/brand", nil)
}

// Update markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).
func (r *BrandResource) Update(ctx context.Context, input *UpdateBrandInput) (*Brand, error) {
	return send[Brand](ctx, r.call, http.MethodPut, "/brand", input)
}

// ---- Webhook'lar ----

type WebhooksResource struct{ call caller }

// Create: yanıttaki SigningSecret ile VerifyWebhook kullanılır.
func (r *WebhooksResource) Create(ctx context.Context, input *CreateWebhookInput) (*CreatedWebhook, error) {
	return send[CreatedWebhook](ctx, r.call, http.MethodPost, "/webhooks", input)
}

func (r *WebhooksResource) Get(ctx context.Context, id string) (*WebhookDetail, error) {
	return get[WebhookDetail](ctx, r.call, "/webhooks/"+seg(id), nil)
}

func (r *WebhooksResource) List(ctx context.Context, query *ListQuery) (*ListResponse[Webhook], error) {
	return get[ListResponse[Webhook]](ctx, r.call, "/webhooks", query)
}

func (r *WebhooksResource) Update(ctx context.Context, id string, input *UpdateWebhookInput) (*WebhookRef, error) {
	return send[WebhookRef](ctx, r.call, http.MethodPatch, "/webhooks/"+seg(id), input)
}

func (r *WebhooksResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/webhooks/"+seg(id), nil)
}

// ---- API anahtarları ----

type APIKeysResource struct{ call caller }

func (r *APIKeysResource) Create(ctx context.Context, input *CreateAPIKeyInput) (*CreatedAPIKey, error) {
	return send[CreatedAPIKey](ctx, r.call, http.MethodPost, "/api-keys", input)
}

func (r *APIKeysResource) List(ctx context.Context, query *ListQuery) (*ListResponse[APIKey], error) {
	return get[ListResponse[APIKey]](ctx, r.call, "/api-keys", query)
}

func (r *APIKeysResource) Remove(ctx context.Context, id string) (*DeletedResponse, error) {
	return send[DeletedResponse](ctx, r.call, http.MethodDelete, "/api-keys/"+seg(id), nil)
}

// ---- Olaylar (otomasyonları tetikler) ----

type EventsResource struct{ call caller }

func eventKey(options []SendEventOptions) string {
	if len(options) > 0 {
		return options[0].IdempotencyKey
	}
	return ""
}

func (r *EventsResource) Send(ctx context.Context, input *SendEventInput, options ...SendEventOptions) (*EventAccepted, error) {
	return call[EventAccepted](ctx, r.call, requestInput{
		method: http.MethodPost, path: "/events", body: input, idempotencyKey: eventKey(options),
	})
}

// Batch en çok 100 olay; biri geçersizse tüm istek 422.
func (r *EventsResource) Batch(ctx context.Context, input []SendEventInput, options ...SendEventOptions) (*EventBatchResponse, error) {
	return call[EventBatchResponse](ctx, r.call, requestInput{
		method: http.MethodPost, path: "/events/batch", body: input, idempotencyKey: eventKey(options),
	})
}

func (r *EventsResource) List(ctx context.Context, query *ListEventsQuery) (*ListResponse[EventItem], error) {
	return get[ListResponse[EventItem]](ctx, r.call, "/events", query)
}
