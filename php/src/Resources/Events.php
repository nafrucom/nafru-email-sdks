<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * Otomasyonları tetikleyen özel olay API'si.
 *
 * @phpstan-import-type SendEventInput from \Nafru\Email\Types
 * @phpstan-import-type EventBatchResponse from \Nafru\Email\Types
 * @phpstan-import-type EventItem from \Nafru\Email\Types
 * @phpstan-import-type ListEventsQuery from \Nafru\Email\Types
 */
final class Events extends Resource
{
    /**
     * `$idempotencyKey`: aynı anahtarla yinelenen istek olayı bir kez işler.
     *
     * @param SendEventInput $input
     * @return array{id: string}
     */
    public function send(array $input, ?string $idempotencyKey = null): array
    {
        return $this->http->request('POST', '/events', body: $input, idempotencyKey: $idempotencyKey);
    }

    /**
     * En çok 100 olay; biri geçersizse tüm istek 422.
     *
     * @param list<SendEventInput> $input
     * @return EventBatchResponse
     */
    public function batch(array $input, ?string $idempotencyKey = null): array
    {
        return $this->http->request('POST', '/events/batch', body: $input, idempotencyKey: $idempotencyKey);
    }

    /**
     * @param ListEventsQuery $query
     * @return array{object: 'list', data: list<EventItem>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/events', $query);
    }
}
