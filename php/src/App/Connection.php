<?php

declare(strict_types=1);

namespace Nafru\Email\App;

use Nafru\Email\Http\Http;
use Nafru\Email\Http\Requester;
use Nafru\Email\NafruException;
use Nafru\Email\Resources\Emails;

/**
 * Bir müşteri bağlantısı adına çağrı yapar. Her denemede `TokenManager` belirteç verir; 401 `invalid_token` (süre dolmuş /
 * yenilenmiş) ise bir kez yenileyip tekrar dener. Yönetim uçları (anahtar, alan adı, kişi, kampanya) bağlantıyla çağrılamaz.
 *
 * @phpstan-import-type ConnectionStatus from \Nafru\Email\Types
 * @phpstan-import-type ConnectionSenders from \Nafru\Email\Types
 * @phpstan-import-type ConnectionTemplate from \Nafru\Email\Types
 */
final class Connection implements Requester
{
    public readonly ConnectionEmails $emails;
    private readonly TokenManager $tokens;
    private readonly Http $http;
    private ?string $current = null;

    /**
     * @internal
     * @param \Closure(\Closure(): ?string): Http $makeHttp
     */
    public function __construct(
        public readonly string $id,
        \Closure $makeHttp,
        Requester $oauth,
        string $clientId,
        #[\SensitiveParameter] string $clientSecret,
        #[\SensitiveParameter] string $refreshToken,
        \Closure $onTokenRefresh,
        string|false $devOutbox = false,
    ) {
        $this->tokens = new TokenManager($oauth, $clientId, $clientSecret, $refreshToken, $onTokenRefresh);
        $this->http = $makeHttp(fn (): string => $this->current = $this->tokens->accessToken());
        $this->emails = new ConnectionEmails(new Emails($this, $devOutbox));
    }

    public function __debugInfo(): array
    {
        return ['id' => $this->id, 'tokens' => $this->tokens, 'current' => $this->current === null ? null : '[REDACTED]'];
    }

    /** @internal */
    public function request(string $method, string $path, array $query = [], mixed $body = null, ?string $idempotencyKey = null): mixed
    {
        try {
            return $this->http->request($method, $path, $query, $body, $idempotencyKey);
        } catch (NafruException $error) {
            if ($error->name !== 'invalid_token' || $this->current === null) {
                throw $error;
            }
            $this->tokens->invalidate($this->current);
            return $this->http->request($method, $path, $query, $body, $idempotencyKey);
        }
    }

    /**
     * `GET /connection`: hazır mı, eksik ne, ücret modu ve müşterinin kurulum adresi.
     *
     * @return ConnectionStatus
     */
    public function status(): array
    {
        return $this->request('GET', '/connection');
    }

    /** @return ConnectionSenders */
    public function senders(): array
    {
        return $this->request('GET', '/senders');
    }

    /**
     * Müşterinin yayınlanmış şablonları ile uygulamanın paketi: anahtar başına tek öğe (müşterinin kendi kopyası paketi gölgeler).
     *
     * @return array{object: 'list', data: list<ConnectionTemplate>, has_more: bool}
     */
    public function templates(): array
    {
        return $this->request('GET', '/templates');
    }
}
