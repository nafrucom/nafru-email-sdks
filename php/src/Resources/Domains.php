<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateDomainInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateDomainInput from \Nafru\Email\Types
 * @phpstan-import-type Domain from \Nafru\Email\Types
 * @phpstan-import-type DomainDetail from \Nafru\Email\Types
 * @phpstan-import-type DomainRef from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Domains extends Resource
{
    /**
     * @param CreateDomainInput $input
     * @return DomainDetail
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/domains', body: $input);
    }

    /** @return DomainDetail */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/domains/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<Domain>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/domains', $query);
    }

    /**
     * @param UpdateDomainInput $input
     * @return DomainRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/domains/' . self::seg($id), body: $input);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/domains/' . self::seg($id));
    }

    /**
     * DNS kayıtlarını denetletir; sonuç `get` ile okunur.
     *
     * @return DomainRef
     */
    public function verify(string $id): array
    {
        return $this->http->request('POST', '/domains/' . self::seg($id) . '/verify');
    }
}
