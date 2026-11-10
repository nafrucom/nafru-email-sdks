<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * @phpstan-import-type CreateTemplateInput from \Nafru\Email\Types
 * @phpstan-import-type UpdateTemplateInput from \Nafru\Email\Types
 * @phpstan-import-type PutTemplateTranslationInput from \Nafru\Email\Types
 * @phpstan-import-type Template from \Nafru\Email\Types
 * @phpstan-import-type TemplateListItem from \Nafru\Email\Types
 * @phpstan-import-type TemplateRef from \Nafru\Email\Types
 * @phpstan-import-type TemplateSaved from \Nafru\Email\Types
 * @phpstan-import-type TemplatePublished from \Nafru\Email\Types
 * @phpstan-import-type TemplateTranslation from \Nafru\Email\Types
 * @phpstan-import-type TemplateTranslationDeleted from \Nafru\Email\Types
 * @phpstan-import-type ListQuery from \Nafru\Email\Types
 * @phpstan-import-type DeletedResponse from \Nafru\Email\Types
 */
final class Templates extends Resource
{
    /**
     * @param CreateTemplateInput $input
     * @return TemplateSaved
     */
    public function create(array $input): array
    {
        return $this->http->request('POST', '/templates', body: $input);
    }

    /**
     * `$idOrAlias`: kimlik ya da takma ad.
     *
     * @return Template
     */
    public function get(string $idOrAlias): array
    {
        return $this->http->request('GET', '/templates/' . self::seg($idOrAlias));
    }

    /**
     * @param ListQuery $query
     * @return array{object: 'list', data: list<TemplateListItem>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/templates', $query);
    }

    /**
     * Taslağı kaydeder; yayımlanana kadar gönderimler eski sürümü kullanır.
     *
     * @param UpdateTemplateInput $input
     * @return TemplateSaved
     */
    public function update(string $idOrAlias, array $input): array
    {
        return $this->http->request('PATCH', '/templates/' . self::seg($idOrAlias), body: $input);
    }

    /** @return DeletedResponse */
    public function remove(string $idOrAlias): array
    {
        return $this->http->request('DELETE', '/templates/' . self::seg($idOrAlias));
    }

    /** @return TemplatePublished */
    public function publish(string $idOrAlias): array
    {
        return $this->http->request('POST', '/templates/' . self::seg($idOrAlias) . '/publish');
    }

    /** @return TemplateRef */
    public function duplicate(string $idOrAlias): array
    {
        return $this->http->request('POST', '/templates/' . self::seg($idOrAlias) . '/duplicate');
    }

    /**
     * Dil taslağını yazar; gönderimler bir sonraki yayından itibaren bu dili kullanır.
     *
     * @param PutTemplateTranslationInput $input
     * @return TemplateTranslation
     */
    public function putTranslation(string $idOrAlias, string $locale, array $input): array
    {
        return $this->http->request('PUT', '/templates/' . self::seg($idOrAlias) . '/translations/' . self::seg($locale), body: $input);
    }

    /** @return TemplateTranslationDeleted */
    public function removeTranslation(string $idOrAlias, string $locale): array
    {
        return $this->http->request('DELETE', '/templates/' . self::seg($idOrAlias) . '/translations/' . self::seg($locale));
    }
}
