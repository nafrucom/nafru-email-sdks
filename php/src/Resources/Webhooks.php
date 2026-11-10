<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateWebhookInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateWebhookInput from \Nafru\Email\Types
 * @phpstan-import-type CreatedWebhook from \Nafru\Email\Types
 * @phpstan-import-type Webhook from \Nafru\Email\Types
 * @phpstan-import-type WebhookDetail from \Nafru\Email\Types
 * @phpstan-import-type WebhookRef from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Webhooks extends Resource
{
    /**
     * Yanıttaki `signing_secret` ile `Webhook::verify` kullanılır.
     *
     * @param CreateWebhookInput $input
     * @return CreatedWebhook
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/webhooks', body: $input);
    }

    /** @return WebhookDetail */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/webhooks/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<Webhook>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/webhooks', $query);
    }

    /**
     * @param UpdateWebhookInput $input
     * @return WebhookRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/webhooks/' . self::seg($id), body: $input);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/webhooks/' . self::seg($id));
    }
}
