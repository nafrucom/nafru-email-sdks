<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

use Nafru\Email\NafruException;

/** Varsayılan taşıyıcı: ext-curl. */
final class CurlTransport implements Transport
{
    public function send(string $method, string $url, array $headers, ?string $body, float $timeoutSeconds): Response
    {
        $handle = curl_init($url);
        $lines = [];
        foreach ($headers as $name => $value) {
            $lines[] = "$name: $value";
        }
        $responseHeaders = [];
        $reason = '';
        $received = '';
        $tooLarge = false;
        curl_setopt_array($handle, [
            CURLOPT_CUSTOMREQUEST => $method,
            CURLOPT_HTTPHEADER => $lines,
            // Yönlendirme izlenmez (Authorization sızmasın); TLS doğrulaması her zaman açık; yalnız http(s).
            CURLOPT_FOLLOWLOCATION => false,
            CURLOPT_SSL_VERIFYPEER => true,
            CURLOPT_SSL_VERIFYHOST => 2,
            CURLOPT_PROTOCOLS => CURLPROTO_HTTP | CURLPROTO_HTTPS,
            CURLOPT_WRITEFUNCTION => static function ($_, string $chunk) use (&$received, &$tooLarge): int {
                if (strlen($received) + strlen($chunk) > Http::MAX_RESPONSE_BYTES) {
                    $tooLarge = true;
                    return 0; // curl aktarımı keser
                }
                $received .= $chunk;
                return strlen($chunk);
            },
            CURLOPT_TIMEOUT_MS => (int) ceil($timeoutSeconds * 1000),
            CURLOPT_HEADERFUNCTION => static function ($_, string $line) use (&$responseHeaders, &$reason): int {
                if (preg_match('#^HTTP/\S+\s+\d+\s*(.*)$#', trim($line), $match)) {
                    // Yönlendirme/100-continue sonrası yeni durum satırı: önceki başlıklar geçersiz.
                    $responseHeaders = [];
                    $reason = $match[1];
                } elseif (str_contains($line, ':')) {
                    [$name, $value] = explode(':', $line, 2);
                    $responseHeaders[strtolower(trim($name))] = trim($value);
                }
                return strlen($line);
            },
        ]);
        if ($body !== null) {
            curl_setopt($handle, CURLOPT_POSTFIELDS, $body);
        }

        $result = curl_exec($handle);
        if ($tooLarge) {
            throw new NafruException(null, 'response_too_large', 'Yanıt gövdesi 10 MB sınırını aşıyor');
        }
        if ($result === false) {
            $errno = curl_errno($handle);
            $error = curl_error($handle);
            throw new TransportException($error !== '' ? $error : 'Sunucuya ulaşılamadı', $errno === CURLE_OPERATION_TIMEDOUT);
        }

        return new Response((int) curl_getinfo($handle, CURLINFO_RESPONSE_CODE), $received, $responseHeaders, $reason);
    }
}
