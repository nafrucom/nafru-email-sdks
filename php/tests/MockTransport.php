<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\Http\Response;
use Nafru\Email\Http\Transport;

/** Sahte taşıyıcı: `route` her çağrıya yanıt verir (Response ya da fırlatır); çağrılar kaydedilir. */
final class MockTransport implements Transport
{
    /** @var list<array{method: string, url: string, headers: array<string, string>, body: ?string, json: mixed}> */
    public array $calls = [];
    private int $index = 0;

    /** @param \Closure(array): Response|list<Response|\Closure(): Response> $route */
    public function __construct(private readonly \Closure|array $route)
    {
    }

    public function send(string $method, string $url, array $headers, ?string $body, float $timeoutSeconds): Response
    {
        $call = ['method' => $method, 'url' => $url, 'headers' => $headers, 'body' => $body, 'json' => $body === null ? null : json_decode($body, true)];
        $this->calls[] = $call;
        if ($this->route instanceof \Closure) {
            return ($this->route)($call);
        }
        $next = $this->route[min($this->index++, count($this->route) - 1)];
        return $next instanceof \Closure ? $next() : $next;
    }
}
