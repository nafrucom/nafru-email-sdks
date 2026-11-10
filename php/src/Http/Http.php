<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

use Nafru\Email\NafruException;

/** @internal */
final class Http implements Requester
{
    private const MAX_BACKOFF_MS = 8000;
    private const BASE_BACKOFF_MS = 300;
    /** Yanıt gövdesi üst sınırı: bozuk/kötü niyetli bir ara katman belleği tüketemesin. */
    public const MAX_RESPONSE_BYTES = 10 * 1024 * 1024;

    private readonly string $base;

    /**
     * @param ?\Closure(): ?string $authorize verilirse `apiKey` yerine her denemede bundan alınan belirteç kullanılır
     *        (`null`: başlık yok); hata `NafruException` olarak istek göndermeden yükselir.
     */
    public function __construct(
        #[\SensitiveParameter] private readonly string $apiKey,
        string $baseUrl,
        private readonly Transport $transport,
        private readonly int $maxRetries,
        private readonly float $timeout,
        private readonly string $userAgent,
        private readonly ?\Closure $authorize = null,
        private readonly DeprecationNotice $deprecation = new DeprecationNotice(),
    ) {
        $this->base = rtrim($baseUrl, '/');
    }

    /** `var_dump`/`print_r` anahtarı göstermesin. */
    public function __debugInfo(): array
    {
        return ['baseUrl' => $this->base, 'apiKey' => '[REDACTED]', 'maxRetries' => $this->maxRetries, 'timeout' => $this->timeout];
    }

    /**
     * Anahtar ve belirteç yalnız https ile gider; http yalnız yerel geliştirme adreslerinde (localhost, *.localhost, 127.0.0.0/8, [::1]).
     */
    public static function assertSecureUrl(string $url, string $label): void
    {
        $parts = parse_url($url);
        $scheme = strtolower($parts['scheme'] ?? '');
        $host = strtolower($parts['host'] ?? '');
        if ($host === '' || ($scheme !== 'https' && !($scheme === 'http' && self::isLoopback($host)))) {
            throw new \InvalidArgumentException("Nafru SDK: $label https kullanmalı (http yalnız localhost için)");
        }
    }

    private static function isLoopback(string $host): bool
    {
        return $host === 'localhost' || str_ends_with($host, '.localhost') || $host === '[::1]'
            || (filter_var($host, FILTER_VALIDATE_IP, FILTER_FLAG_IPV4) !== false && str_starts_with($host, '127.'));
    }

    /** Yalnız dolu değerler (`null` ve `''` atlanır); `bool` `true`/`false` olarak gider. */
    public static function serializeQuery(array $query): string
    {
        $params = [];
        foreach ($query as $key => $value) {
            if ($value === null || $value === '') {
                continue;
            }
            $params[$key] = is_bool($value) ? ($value ? 'true' : 'false') : (string) $value;
        }
        $text = http_build_query($params);
        return $text === '' ? '' : "?$text";
    }

    /**
     * `GET` ve `DELETE` yinelenebilir; `POST`/`PATCH` yalnız istek işlenmeden reddedildiyse (429) ya da `Idempotency-Key` taşıyorsa
     * yinelenir: anahtarsız sunucu hatasında e-posta çift gidebilir.
     */
    private static function isSafeToRetry(string $method, ?string $idempotencyKey): bool
    {
        return $method === 'GET' || $method === 'DELETE' || $idempotencyKey !== null;
    }

    public function request(string $method, string $path, array $query = [], mixed $body = null, ?string $idempotencyKey = null): mixed
    {
        $headers = ['accept' => 'application/json', 'user-agent' => $this->userAgent];
        if ($this->authorize === null) {
            $headers['authorization'] = "Bearer {$this->apiKey}";
        }
        $payload = null;
        if ($body !== null) {
            $payload = json_encode($body, JSON_THROW_ON_ERROR | JSON_UNESCAPED_SLASHES | JSON_UNESCAPED_UNICODE);
            $headers['content-type'] = 'application/json';
        }
        if ($idempotencyKey !== null) {
            // Başlık enjeksiyonu: CR/LF ve diğer denetim karakterleri başlığa girmez.
            if ($idempotencyKey === '' || preg_match('/[\x00-\x1F\x7F]/', $idempotencyKey)) {
                throw new NafruException(null, 'invalid_argument', 'idempotencyKey boş olamaz ve denetim karakteri içeremez');
            }
            $headers['idempotency-key'] = $idempotencyKey;
        }
        $url = $this->base . $path . self::serializeQuery($query);
        $safe = self::isSafeToRetry($method, $idempotencyKey);

        for ($attempt = 0; ; $attempt++) {
            if ($this->authorize !== null) {
                $token = ($this->authorize)();
                unset($headers['authorization']);
                if ($token !== null) {
                    $headers['authorization'] = "Bearer $token";
                }
            }
            $last = $attempt >= $this->maxRetries;

            try {
                $response = $this->transport->send($method, $url, $headers, $payload, $this->timeout);
            } catch (TransportException $cause) {
                if (!$last && $safe) {
                    self::sleep(self::BASE_BACKOFF_MS * 2 ** $attempt);
                    continue;
                }
                throw $cause->timedOut ? NafruException::timeout($this->timeout) : NafruException::network($cause->getMessage(), $cause);
            }

            $this->deprecation->check($response);
            if (strlen($response->body) > self::MAX_RESPONSE_BYTES) {
                throw new NafruException($response->status, 'response_too_large', 'Yanıt gövdesi 10 MB sınırını aşıyor');
            }
            // API yönlendirmez; izlemek Authorization başlığını başka bir sunucuya sızdırabilir.
            if ($response->status >= 300 && $response->status < 400) {
                throw new NafruException($response->status, 'unexpected_redirect', "Beklenmeyen yönlendirme (HTTP {$response->status}); izlenmedi");
            }
            $decoded = self::decode($response->body);
            if ($response->status >= 200 && $response->status < 300) {
                return $decoded;
            }

            $error = NafruException::fromResponse($response, $decoded);
            $retryable = $response->status === 429 || ($response->status >= 500 && $safe);
            if ($retryable && !$last) {
                self::sleep($error->retryAfter !== null ? $error->retryAfter * 1000 : self::BASE_BACKOFF_MS * 2 ** $attempt);
                continue;
            }
            throw $error;
        }
    }

    private static function decode(string $text): mixed
    {
        if ($text === '') {
            return null;
        }
        try {
            return json_decode($text, true, 512, JSON_THROW_ON_ERROR);
        } catch (\JsonException) {
            return null;
        }
    }

    private static function sleep(int|float $ms): void
    {
        usleep((int) (min($ms, self::MAX_BACKOFF_MS) * 1000));
    }
}
