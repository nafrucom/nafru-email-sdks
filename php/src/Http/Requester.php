<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

/** Kaynakların istek attığı tek yüzey (API anahtarlı istemci ya da bağlantı). */
interface Requester
{
    /**
     * Çözülmüş JSON gövdeyi döndürür (boş gövdede `null`); hata `NafruException` fırlatır.
     *
     * @param array<string, mixed> $query
     */
    public function request(string $method, string $path, array $query = [], mixed $body = null, ?string $idempotencyKey = null): mixed;
}
