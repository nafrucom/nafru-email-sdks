<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateApiKeyInput from \Nafru\Email\Types
 * @phpstan-import-type CreatedApiKey from \Nafru\Email\Types
 * @phpstan-import-type ApiKey from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class ApiKeys extends Resource
{
    /**
     * @param CreateApiKeyInput $input
     * @return CreatedApiKey
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/api-keys', body: $input);
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<ApiKey>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/api-keys', $query);
    }

    /** @return DeletedResponse */
    public function remove(string $id): array
    {
        return $this->http->request('DELETE', '/api-keys/' . self::seg($id));
    }
}
