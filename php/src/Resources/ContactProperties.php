<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateContactPropertyInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateContactPropertyInput from \Nafru\Email\Types
 * @phpstan-import-type ContactProperty from \Nafru\Email\Types
 * @phpstan-import-type ContactPropertyDetail from \Nafru\Email\Types
 * @phpstan-import-type ContactPropertyRef from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class ContactProperties extends Resource
{
    /**
     * @param CreateContactPropertyInput $input
     * @return ContactPropertyRef
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/contact-properties', body: $input);
    }

    /** @return ContactPropertyDetail */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/contact-properties/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<ContactProperty>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/contact-properties', $query);
    }

    /**
     * @param UpdateContactPropertyInput $input
     * @return ContactPropertyRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/contact-properties/' . self::seg($id), body: $input);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/contact-properties/' . self::seg($id));
    }
}
