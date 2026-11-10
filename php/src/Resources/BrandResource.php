<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

/**
 * Çalışma alanının markası: logo, renkler, yazı tipi, altbilgi. Şablonlar markayı `brand` alanıyla devralır.
 *
 * @phpstan-import-type Brand from \Nafru\Email\Types
 * @phpstan-import-type UpdateBrandInput from \Nafru\Email\Types
 */
final class BrandResource extends Resource
{
    /** @return Brand */
    public function get(): array
    {
        return $this->http->request('GET', '/brand');
    }

    /**
     * Markanın TAMAMINI değiştirir (gönderilmeyen alan "ayarlanmadı" olur).
     *
     * @param UpdateBrandInput $input
     * @return Brand
     */
    public function update(array $input): array
    {
        return $this->http->request('PUT', '/brand', body: $input === [] ? new \stdClass() : $input);
    }
}
