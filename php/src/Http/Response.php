<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

final class Response
{
    /** @var array<string, string> küçük harfli başlık adları */
    public readonly array $headers;

    /** @param array<string, string> $headers */
    public function __construct(
        public readonly int $status,
        public readonly string $body = '',
        array $headers = [],
        public readonly string $reasonPhrase = '',
    ) {
        $this->headers = array_change_key_case($headers, CASE_LOWER);
    }

    /** @param mixed $data JSON'a çevrilecek gövde (testler için kısayol). */
    public static function json(mixed $data, int $status = 200, array $headers = []): self
    {
        return new self($status, json_encode($data, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES), ['content-type' => 'application/json'] + $headers);
    }
}
