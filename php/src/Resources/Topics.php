<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateTopicInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateTopicInput from \Nafru\Email\Types
 * @phpstan-import-type Topic from \Nafru\Email\Types
 * @phpstan-import-type TopicDetail from \Nafru\Email\Types
 * @phpstan-import-type TopicRef from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Topics extends Resource
{
    /**
     * @param CreateTopicInput $input
     * @return TopicRef
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/topics', body: $input);
    }

    /** @return TopicDetail */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/topics/' . self::seg($id));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<Topic>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/topics', $query);
    }

    /**
     * @param UpdateTopicInput $input
     * @return TopicRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/topics/' . self::seg($id), body: $input);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/topics/' . self::seg($id));
    }
}
