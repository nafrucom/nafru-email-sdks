<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

/** HTTP taşıyıcısı: test, proxy ya da kendi istemciniz (Guzzle vb.) için değiştirilebilir. */
interface Transport
{
    /**
     * Yanıtı döndürür (4xx/5xx dahil); yalnız ağ hatası ya da zaman aşımında `TransportException` fırlatır.
     *
     * @param array<string, string> $headers küçük harfli başlık adları
     */
    public function send(string $method, string $url, array $headers, ?string $body, float $timeoutSeconds): Response;
}
