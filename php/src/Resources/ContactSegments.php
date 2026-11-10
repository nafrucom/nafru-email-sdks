<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type Segment from \Nafru\Email\Types
 */
final class ContactSegments extends Resource
{
    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<Segment>, has_more: bool}
     */
    public function list(string $idOrEmail, array $query = []): array
    {
        return $this->http->request('GET', '/contacts/' . self::seg($idOrEmail) . '/segments', $query);
    }

    /**
     * Kişiyi statik segmente ekler (dinamik segmentte 422).
     *
     * @return array{id: string}
     */
    public function add(string $idOrEmail, string $segmentId): array
    {
        return $this->http->request('POST', '/contacts/' . self::seg($idOrEmail) . '/segments/' . self::seg($segmentId));
    }

    /** @return array{id: string, deleted: true} */
    public function remove(string $idOrEmail, string $segmentId): array
    {
        return $this->http->request('DELETE', '/contacts/' . self::seg($idOrEmail) . '/segments/' . self::seg($segmentId));
    }
}
