<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateSegmentInput from \Nafru\Email\Types
 * @phpstan-import-type Segment from \Nafru\Email\Types
 * @phpstan-import-type SegmentDetail from \Nafru\Email\Types
 * @phpstan-import-type SegmentRef from \Nafru\Email\Types
 * @phpstan-import-type Contact from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Segments extends Resource
{
    /**
     * @param CreateSegmentInput $input
     * @return SegmentRef
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/segments', body: $input);
    }

    /** @return SegmentDetail */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/segments/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<Segment>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/segments', $query);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/segments/' . self::seg($id));
    }

    /**
     * Segmentin kişileri; sayfalama kimlik sırasıyla, yalnız `after`.
     *
     * @param array{limit?: int, after?: string} $query
     * @return array{object: 'list', data: list<Contact>, has_more: bool}
     */
    public function contacts(string $id, array $query = []): array
    {
        return $this->http->request('GET', '/segments/' . self::seg($id) . '/contacts', $query);
    }
}
