<?php

declare(strict_types=1);

namespace Nafru\Email\App;

use Nafru\Email\Http\Requester;
use Nafru\Email\NafruException;

/**
 * Bağlantının erişim belirtecini tutar ve yeniler. Aynı anda tek yenileme yapılır (tek uçuş): dönüşlü yenileme belirteci ikinci
 * bir yenilemede "yeniden kullanım" sayılır ve bağlantıyı iptal ettirirdi.
 *
 * @internal
 */
final class TokenManager
{
    /** Süre dolmadan bu kadar önce yenilenir (saat farkı ve ağ gecikmesi payı). */
    private const EARLY_REFRESH_SECONDS = 30;

    private ?string $accessToken = null;
    private float $expiresAt = 0;
    private bool $refreshing = false;
    /** Yenileme sunucuda başarılı oldu ama yeni yenileme belirteci saklanamadı: eski belirteç artık geçersiz, bu kaybolmamalı. */
    private bool $unpersisted = false;

    /** @param \Closure(array{refreshToken: string}): void $onTokenRefresh */
    public function __construct(
        private readonly Requester $oauth,
        private readonly string $clientId,
        #[\SensitiveParameter] private readonly string $clientSecret,
        #[\SensitiveParameter] private string $refreshToken,
        private readonly \Closure $onTokenRefresh,
    ) {
    }

    public function __debugInfo(): array
    {
        return ['clientId' => $this->clientId, 'clientSecret' => '[REDACTED]', 'refreshToken' => '[REDACTED]', 'accessToken' => $this->accessToken === null ? null : '[REDACTED]', 'expiresAt' => $this->expiresAt];
    }

    /** Geçerli erişim belirteci; yoksa ya da dolmak üzereyse yeniler. */
    public function accessToken(): string
    {
        if ($this->unpersisted) {
            $this->persist();
        }
        if ($this->accessToken !== null && microtime(true) < $this->expiresAt - self::EARLY_REFRESH_SECONDS) {
            return $this->accessToken;
        }
        return $this->refresh();
    }

    /** Sunucu 401 `invalid_token` dedi: eldeki belirteci at ve yenile (aynı bayat belirteçle gelen ikinci çağrı yenilenmişi alır). */
    public function invalidate(string $stale): string
    {
        if ($this->accessToken === $stale) {
            $this->accessToken = null;
        }
        return $this->accessToken ?? $this->refresh();
    }

    private function persist(): void
    {
        try {
            ($this->onTokenRefresh)(['refreshToken' => $this->refreshToken]);
            $this->unpersisted = false;
        } catch (\Throwable $cause) {
            $this->unpersisted = true;
            throw new NafruException(null, 'token_persist_failed', 'Yeni yenileme belirteci saklanamadı: ' . $cause->getMessage(), previous: $cause);
        }
    }

    private function refresh(): string
    {
        // shortcut: PHP isteği tek iş parçacıklıdır; yeniden giriş (Fiber) olursa ikinci yenilemeyi göndermek yerine hata verir.
        if ($this->refreshing) {
            throw new NafruException(null, 'application_error', 'Belirteç yenilemesi zaten sürüyor');
        }
        $this->refreshing = true;
        try {
            $data = $this->oauth->request('POST', '/oauth/token', body: [
                'grant_type' => 'refresh_token',
                'client_id' => $this->clientId,
                'client_secret' => $this->clientSecret,
                'refresh_token' => $this->refreshToken,
            ]);
        } catch (NafruException $error) {
            // Geçersiz/tüketilmiş belirteç ya da iptal: kalıcı hata. Ağ ve 5xx geçici hata olarak olduğu gibi yükselir.
            if ($error->name === 'invalid_grant' || $error->name === 'connection_revoked'
                || ($error->statusCode === 403 && $error->name !== 'rate_limit_exceeded')) {
                throw $error->withName('connection_revoked', 'Bağlantı iptal edilmiş ya da yenileme belirteci geçersiz; müşterinin yeniden bağlanması gerekir.');
            }
            throw $error;
        } finally {
            $this->refreshing = false;
        }
        $this->refreshToken = $data['refresh_token'];
        $this->accessToken = $data['access_token'];
        $this->expiresAt = microtime(true) + $data['expires_in'];
        $this->persist();
        return $this->accessToken;
    }
}
