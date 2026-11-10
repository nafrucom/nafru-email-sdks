<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateBroadcastInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateBroadcastInput from \Nafru\Email\Types
 * @phpstan-import-type SendBroadcastInput from \Nafru\Email\Types
 * @phpstan-import-type Broadcast from \Nafru\Email\Types
 * @phpstan-import-type BroadcastListItem from \Nafru\Email\Types
 * @phpstan-import-type BroadcastRef from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Broadcasts extends Resource
{
    /**
     * Taslak oluşturur; `send: true` ile aynı istekte gönderir.
     *
     * @param CreateBroadcastInput $input
     * @return BroadcastRef
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/broadcasts', body: $input);
    }

    /** @return Broadcast */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/broadcasts/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<BroadcastListItem>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/broadcasts', $query);
    }

    /**
     * Yalnız taslakta (aksi 409).
     *
     * @param UpdateBroadcastInput $input
     * @return BroadcastRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/broadcasts/' . self::seg($id), body: $input);
    }

    /**
     * Yalnız taslakta (aksi 409).
     *
     * @return DeletedResponse
     */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/broadcasts/' . self::seg($id));
    }

    /**
     * @param SendBroadcastInput $input
     * @return BroadcastRef
     */
    public function send(string $id, array $input = []): array
    {
        // Boş PHP dizisi JSON'da `[]` olur; sunucu nesne bekler.
        return $this->http->request('POST', '/broadcasts/' . self::seg($id) . '/send', body: $input === [] ? new \stdClass() : $input);
    }

    /** @return BroadcastRef */
    public function cancel(string $id): array
    {
        return $this->http->request('POST', '/broadcasts/' . self::seg($id) . '/cancel');
    }
}
