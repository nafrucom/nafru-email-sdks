<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

use Nafru\Email\Http\Requester;

/**
 * Kişi uçlarında `id` yerine e-posta adresi de verilebilir.
 *
 * @phpstan-import-type CreateContactInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateContactInput from \Nafru\Email\Types
 * @phpstan-import-type ListContactsQuery from \Nafru\Email\Types
 * @phpstan-import-type Contact from \Nafru\Email\Types
 * @phpstan-import-type ContactDetail from \Nafru\Email\Types
 * @phpstan-import-type ContactRef from \Nafru\Email\Types
 * @phpstan-import-type DeletedContact from \Nafru\Email\Types
 */
final class Contacts extends Resource
{
    public readonly ContactSegments $segments;
    public readonly ContactTopics $topics;

    public function __construct(Requester $http)
    {
        parent::__construct($http);
        $this->segments = new ContactSegments($http);
        $this->topics = new ContactTopics($http);
    }

    /**
     * @param CreateContactInput $input
     * @return ContactRef
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/contacts', body: $input);
    }

    /** @return ContactDetail */
    public function get(string $idOrEmail): array
    {
        return $this->http->request('GET', '/contacts/' . self::seg($idOrEmail));
    }

    /**
     * @param ListContactsQuery $query
     * @return array{object: 'list', data: list<Contact>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/contacts', $query);
    }

    /**
     * @param UpdateContactInput $input
     * @return ContactRef
     */
    public function update(string $idOrEmail, array $input): array
    {
        return $this->http->request('PATCH', '/contacts/' . self::seg($idOrEmail), body: $input);
    }

    /** @return DeletedContact */
    public function remove(string $idOrEmail): array
    {
        return $this->http->request('DELETE', '/contacts/' . self::seg($idOrEmail));
    }
}
