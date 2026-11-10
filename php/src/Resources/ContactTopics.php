<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type ContactTopic from \Nafru\Email\Types
 * @phpstan-import-type UpdateContactTopicsInput from \Nafru\Email\Types
 * @phpstan-import-type ContactRef from \Nafru\Email\Types
 */
final class ContactTopics extends Resource
{
    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<ContactTopic>, has_more: bool}
     */
    public function list(string $idOrEmail, array $query = []): array
    {
        return $this->http->request('GET', '/contacts/' . self::seg($idOrEmail) . '/topics', $query);
    }

    /**
     * @param UpdateContactTopicsInput $input
     * @return ContactRef
     */
    public function update(string $idOrEmail, array $input): array
    {
        // Sunucu gövdede çıplak dizi bekler.
        return $this->http->request('PATCH', '/contacts/' . self::seg($idOrEmail) . '/topics', body: $input['topics']);
    }
}
