<?php

declare(strict_types=1);

namespace Nafru\Email;

/**
 * İstek ve yanıt modelleri: PHPStan/Psalm dizi şekilleri (`@phpstan-import-type Email from Types`). Alanlar API'deki gibi
 * `snake_case`'tir; dönüştürme katmanı yoktur, belgelerle ve ağ trafiğiyle birebir aynı görünür. Çalışma anında yalın dizidir.
 *
 * Ortak
 * @phpstan-type ListQuery array{limit?: int, after?: string, before?: string}
 * @phpstan-type DeletedResponse array{object: string, id: string, deleted: true}
 * @phpstan-type Tag array{name: string, value: string}
 * @phpstan-type IdRef array{id: string}
 *
 * E-postalar
 * @phpstan-type Attachment array{content?: string, path?: string, filename?: string, content_type?: string, content_id?: string}
 * @phpstan-type SendEmailInput array{from?: string, to: string|list<string>, cc?: string|list<string>, bcc?: string|list<string>, reply_to?: string|list<string>, subject?: string, headers?: array<string, string>, tags?: list<Tag>, scheduled_at?: string, html?: string, text?: string, attachments?: list<Attachment>, template?: array{id: string, variables?: array<string, string|int|float>}}
 * @phpstan-type BatchEmailItem array{from: string, to: string|list<string>, cc?: string|list<string>, bcc?: string|list<string>, reply_to?: string|list<string>, subject: string, headers?: array<string, string>, tags?: list<Tag>, scheduled_at?: string, html?: string, text?: string}
 * @phpstan-type SendEmailResponse array{id: string}
 * @phpstan-type BatchEmailResponse array{data: list<IdRef>}
 * @phpstan-type EmailListItem array{id: string, to: list<string>, from: string, created_at: string, subject: string, bcc: list<string>|null, cc: list<string>|null, reply_to: list<string>|null, last_event: string, scheduled_at: string|null, message_id: string|null}
 * @phpstan-type EmailEvent array{id: string, type: string, created_at: string, detail: array<string, mixed>}
 * @phpstan-type Email array{object: 'email', id: string, to: list<string>, from: string, created_at: string, subject: string, bcc: list<string>|null, cc: list<string>|null, reply_to: list<string>|null, last_event: string, scheduled_at: string|null, message_id: string|null, html: string|null, text: string|null, tags: list<Tag>, events: list<EmailEvent>}
 * @phpstan-type ListEmailsQuery array{limit?: int, after?: string, before?: string, status?: string}
 * @phpstan-type EmailRef array{object: 'email', id: string}
 *
 * Alan adları
 * @phpstan-type DomainStatus 'not_started'|'pending'|'verified'|'failed'|'temporary_failure'
 * @phpstan-type DomainRecord array{record: 'SPF'|'DKIM'|'Tracking', name: string, type: 'MX'|'TXT'|'CNAME', value: string, ttl: 'Auto', status: DomainStatus, priority?: int}
 * @phpstan-type Domain array{id: string, name: string, status: DomainStatus, created_at: string, region: string, capabilities: array{sending: 'enabled', receiving: 'disabled'}, open_tracking: bool, click_tracking: bool, tls: 'opportunistic'|'enforced', tracking_subdomain: string|null}
 * @phpstan-type DomainDetail array{object: 'domain', id: string, name: string, status: DomainStatus, created_at: string, region: string, capabilities: array{sending: 'enabled', receiving: 'disabled'}, open_tracking: bool, click_tracking: bool, tls: 'opportunistic'|'enforced', tracking_subdomain: string|null, records: list<DomainRecord>}
 * @phpstan-type CreateDomainInput array{name: string, region?: string, open_tracking?: bool, click_tracking?: bool, tls?: 'opportunistic'|'enforced', tracking_subdomain?: string}
 * @phpstan-type UpdateDomainInput array{open_tracking?: bool, click_tracking?: bool, tls?: 'opportunistic'|'enforced', tracking_subdomain?: string|null}
 * @phpstan-type DomainRef array{object: 'domain', id: string}
 *
 * Kişiler
 * @phpstan-type PropertyValue string|int|float|null
 * @phpstan-type Contact array{id: string, email: string, first_name: string|null, last_name: string|null, unsubscribed: bool, locale: string|null, created_at: string}
 * @phpstan-type ContactDetail array{object: 'contact', id: string, email: string, first_name: string|null, last_name: string|null, unsubscribed: bool, locale: string|null, created_at: string, properties: array<string, array{type: 'string'|'number', value: string|int|float}>}
 * @phpstan-type CreateContactInput array{email: string, first_name?: string|null, last_name?: string|null, unsubscribed?: bool, locale?: string|null, properties?: array<string, PropertyValue>, segments?: list<IdRef>, topics?: list<array{id: string, subscription: 'opt_in'|'opt_out'}>}
 * @phpstan-type UpdateContactInput array{first_name?: string|null, last_name?: string|null, unsubscribed?: bool, locale?: string|null, properties?: array<string, PropertyValue>}
 * @phpstan-type ListContactsQuery array{limit?: int, after?: string, before?: string, search?: string}
 * @phpstan-type ContactRef array{object: 'contact', id: string}
 * @phpstan-type DeletedContact array{object: 'contact', contact: string, deleted: true}
 * @phpstan-type ContactProperty array{id: string, key: string, type: 'string'|'number', fallback_value: string|int|float|null, created_at: string}
 * @phpstan-type ContactPropertyDetail array{object: 'contact_property', id: string, key: string, type: 'string'|'number', fallback_value: string|int|float|null, created_at: string}
 * @phpstan-type CreateContactPropertyInput array{key: string, type: 'string'|'number', fallback_value?: string|int|float|null}
 * @phpstan-type UpdateContactPropertyInput array{fallback_value?: string|int|float|null}
 * @phpstan-type ContactPropertyRef array{object: 'contact_property', id: string}
 *
 * Segmentler
 * @phpstan-type Segment array{id: string, name: string, created_at: string, type: 'static'|'dynamic', filter: array<string, mixed>|null}
 * @phpstan-type SegmentDetail array{object: 'segment', id: string, name: string, created_at: string, type: 'static'|'dynamic', filter: array<string, mixed>|null}
 * @phpstan-type CreateSegmentInput array{name: string, filter?: array<string, mixed>}
 * @phpstan-type SegmentRef array{object: 'segment', id: string, name: string}
 *
 * Konular
 * @phpstan-type TopicSubscription 'opt_in'|'opt_out'
 * @phpstan-type Topic array{id: string, name: string, description: string|null, default_subscription: TopicSubscription, visibility: 'public'|'private', double_opt_in: bool, created_at: string}
 * @phpstan-type TopicDetail array{object: 'topic', id: string, name: string, description: string|null, default_subscription: TopicSubscription, visibility: 'public'|'private', double_opt_in: bool, created_at: string}
 * @phpstan-type CreateTopicInput array{name: string, default_subscription: TopicSubscription, description?: string|null, visibility?: 'public'|'private', double_opt_in?: bool}
 * @phpstan-type UpdateTopicInput array{name?: string, description?: string|null, visibility?: 'public'|'private', double_opt_in?: bool}
 * @phpstan-type TopicRef array{object: 'topic', id: string}
 * @phpstan-type ContactTopic array{id: string, name: string, description: string|null, subscription: TopicSubscription, status: 'opt_in'|'opt_out'|'pending'}
 * @phpstan-type UpdateContactTopicsInput array{topics: list<array{id: string, subscription: TopicSubscription}>}
 *
 * Kampanyalar
 * @phpstan-type BroadcastStatus 'draft'|'scheduled'|'sending'|'sent'|'paused'|'canceled'|'failed'
 * Tekrar kuralı; saat (`HH:MM`) çalışma alanının saat dilimindedir. `weekly.days`: 0 = pazar … 6 = cumartesi; `monthly.day`: 1–31; `interval.every_days`: 1–365.
 * @phpstan-type BroadcastRecurrence array{type: 'weekly', days: list<int>, time: string}|array{type: 'monthly', day: int, time: string}|array{type: 'interval', every_days: int, time: string}
 * `{{{data.*}}}` değişkenlerinin kaynağı. Yanıtta bilinmeyen `type` gelirse dizi olduğu gibi döner (çalışma anında denetim yok).
 * @phpstan-type BroadcastDataSourceInput array{type: 'manual'}|array{type: 'url', url: string, header_name?: string|null, header_value?: string|null}|array{type: 'webhook', regenerate_secret?: bool}
 * @phpstan-type BroadcastDataSource array{type: 'manual'}|array{type: 'url', url: string, header_name: string|null, has_header_value: bool}|array{type: 'webhook', trigger_url: string, secret: string}|array{type: string}
 * @phpstan-type BroadcastListItem array{id: string, name: string, segment_id: string, audience_id: string, subject: string, status: BroadcastStatus, created_at: string, scheduled_at: string|null, sent_at: string|null, recurrence: BroadcastRecurrence|null, trigger_state: 'active'|'paused'|null, next_run_at: string|null, parent_id: string|null}
 * @phpstan-type Broadcast array{object: 'broadcast', id: string, name: string, segment_id: string, audience_id: string, subject: string, status: BroadcastStatus, created_at: string, scheduled_at: string|null, sent_at: string|null, recurrence: BroadcastRecurrence|null, trigger_state: 'active'|'paused'|null, next_run_at: string|null, parent_id: string|null, from: string, reply_to: list<string>|null, preview_text: string|null, topic_id: string|null, template_id: string|null, html: string|null, text: string|null, open_tracking: bool, click_tracking: bool, finished_at: string|null, failure_reason: string|null, data: array<string, mixed>|null, data_source: BroadcastDataSource|null}
 * `null` alanı temizler, verilmeyen alan değişmez (`recurrence`, `data`, `data_source`).
 * @phpstan-type CreateBroadcastInput array{name?: string, segment_id: string, topic_id?: string, from: string, subject?: string, reply_to?: string|list<string>, html?: string, text?: string, template_id?: string, preview_text?: string|null, send?: bool, scheduled_at?: string, open_tracking?: bool, click_tracking?: bool, data?: array<string, mixed>|\stdClass|null, data_source?: BroadcastDataSourceInput|null, recurrence?: BroadcastRecurrence|null}
 * @phpstan-type UpdateBroadcastInput array{name?: string, segment_id?: string, topic_id?: string|null, from?: string, subject?: string, reply_to?: list<string>, html?: string, text?: string, preview_text?: string|null, open_tracking?: bool, click_tracking?: bool, data?: array<string, mixed>|\stdClass|null, data_source?: BroadcastDataSourceInput|null, recurrence?: BroadcastRecurrence|null}
 * @phpstan-type SendBroadcastInput array{scheduled_at?: string, data?: array<string, mixed>|\stdClass}
 * @phpstan-type BroadcastRef array{object: 'broadcast', id: string}
 *
 * Marka
 * @phpstan-type BrandFontKey 'MODERN_SANS'|'BOOK_SANS'|'ORGANIC_SANS'|'GEOMETRIC_SANS'|'HEAVY_SANS'|'ROUNDED_SANS'|'MODERN_SERIF'|'BOOK_SERIF'|'MONOSPACE'
 * @phpstan-type BrandSocialLink array{network: 'website'|'x'|'facebook'|'instagram'|'linkedin'|'youtube'|'github'|'tiktok', url: string}
 * @phpstan-type Brand array{object: 'brand', configured: bool, logo_asset_id: string|null, logo_url: string|null, logo_dark_asset_id: string|null, logo_dark_url: string|null, logo_width: int, logo_align: 'left'|'center'|'right', header_enabled: bool, accent_color: string, text_color: string, backdrop_color: string, canvas_color: string, link_color: string, font_family: BrandFontKey, button_style: 'rectangle'|'rounded'|'pill', content_width: int, footer_text: string|null, legal_text: string|null, postal_address: string|null, website_url: string|null, social_links: list<BrandSocialLink>, unsubscribe_label: string, updated_at: string|null}
 * @phpstan-type UpdateBrandInput array{logo_asset_id?: string|null, logo_dark_asset_id?: string|null, logo_width?: int|null, logo_align?: 'left'|'center'|'right'|null, header_enabled?: bool, accent_color?: string|null, text_color?: string|null, backdrop_color?: string|null, canvas_color?: string|null, link_color?: string|null, font_family?: BrandFontKey|null, button_style?: 'rectangle'|'rounded'|'pill'|null, content_width?: int|null, footer_text?: string|null, legal_text?: string|null, postal_address?: string|null, website_url?: string|null, social_links?: list<BrandSocialLink>, unsubscribe_label?: string|null}
 * @phpstan-type TemplateBrandOverride array{accent_color?: string, text_color?: string, backdrop_color?: string, canvas_color?: string, font_family?: BrandFontKey, link_color?: string, content_width?: int, show_header?: bool, show_footer?: bool}
 * @phpstan-type TemplateBrand array{mode: 'inherit'|'custom'|'none', override?: TemplateBrandOverride|null}
 *
 * Şablonlar
 * @phpstan-type TemplateListItem array{id: string, name: string, alias: string|null, type: 'design'|'html', status: 'draft'|'published', subject: string|null, current_version: int|null, has_unpublished_changes: bool, published_at: string|null, created_at: string, updated_at: string}
 * @phpstan-type TemplateVariable array{key: string, type: 'string', fallback_value: string|null}
 * @phpstan-type Template array{object: 'template', id: string, name: string, alias: string|null, type: 'design'|'html', status: 'draft'|'published', subject: string|null, current_version: int|null, has_unpublished_changes: bool, published_at: string|null, created_at: string, updated_at: string, preview_text: string|null, html: string, text: string|null, design: mixed, revision: int, variables: list<TemplateVariable>, brand: array{mode: 'inherit'|'custom'|'none', override: TemplateBrandOverride|null}}
 * @phpstan-type CreateTemplateInput array{name: string, alias?: string, subject?: string|null, preview_text?: string|null, html: string, text?: string|null, brand?: TemplateBrand}
 * @phpstan-type UpdateTemplateInput array{revision?: int, name?: string, alias?: string|null, subject?: string|null, preview_text?: string|null, html?: string, text?: string|null, brand?: TemplateBrand}
 * @phpstan-type TemplateRef array{object: 'template', id: string}
 * @phpstan-type TemplateSaved array{object: 'template', id: string, revision: int}
 * @phpstan-type TemplatePublished array{object: 'template', id: string, version: int, version_id: string, revision: int}
 * @phpstan-type PutTemplateTranslationInput array{subject?: string|null, preview_text?: string|null, html: string, text?: string|null}
 * @phpstan-type TemplateTranslation array{locale: string, subject: string|null, preview_text: string|null, design_revision: int, updated_at: string}
 * @phpstan-type TemplateTranslationDeleted array{object: 'template_translation', locale: string, deleted: true}
 *
 * Webhook'lar
 * @phpstan-type Webhook array{id: string, endpoint: string, created_at: string, status: 'enabled'|'disabled', events: list<string>}
 * @phpstan-type WebhookDetail array{object: 'webhook', id: string, endpoint: string, created_at: string, status: 'enabled'|'disabled', events: list<string>, signing_secret: string}
 * @phpstan-type CreateWebhookInput array{endpoint: string, events: list<string>}
 * @phpstan-type CreatedWebhook array{object: 'webhook', id: string, signing_secret: string}
 * @phpstan-type UpdateWebhookInput array{endpoint?: string, events?: list<string>, status?: 'enabled'|'disabled'}
 * @phpstan-type WebhookRef array{object: 'webhook', id: string}
 * @phpstan-type WebhookPayload array{type: string, created_at: string, data: array<string, mixed>}
 *
 * API anahtarları
 * @phpstan-type ApiKey array{id: string, name: string, created_at: string, last_used_at: string|null, permission: 'full_access'|'sending_access', domain_id: string|null, token_prefix: string}
 * @phpstan-type CreateApiKeyInput array{name: string, permission?: 'full_access'|'sending_access', domain_id?: string}
 * @phpstan-type CreatedApiKey array{id: string, token: string}
 *
 * Olaylar
 * @phpstan-type EventProperties array<string, string|int|float|bool|null>
 * @phpstan-type SendEventInput array{name: string, contact: array{email: string}|array{id: string}, properties?: EventProperties, occurred_at?: string, unsubscribed?: bool}
 * @phpstan-type EventBatchResponse array{data: list<IdRef>}
 * @phpstan-type EventItem array{id: string, name: string, contact_id: string, email: string, properties: EventProperties, source: 'api'|'system', occurred_at: string, created_at: string}
 * @phpstan-type ListEventsQuery array{limit?: int, after?: string, before?: string, name?: string, contact_id?: string, email?: string}
 *
 * Nafru ile bağlan
 * @phpstan-type AppScope 'emails.send'|'emails.read'|'templates.read'|'domains.read'|'senders.read'|'connection.read'
 * @phpstan-type AuthorizeUrl array{url: string, codeVerifier: string}
 * @phpstan-type ConnectionStatus array{object: 'connection', id: string, ready: bool, missing: list<string>, hints: list<string>, scopes: list<AppScope>, billing_mode: 'customer_pays'|'app_pays', setup_url: string, workspace: array{name: string}}
 * @phpstan-type ConnectionSenders array{domains: list<array{id: string, name: string}>, default_from: string|null}
 * @phpstan-type ConnectionTemplate array{key: string, name: string, source: 'workspace'|'pack', customized_from_pack: bool}
 */
final class Types
{
    private function __construct()
    {
    }
}
