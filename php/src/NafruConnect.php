<?php

declare(strict_types=1);

namespace Nafru\Email;

use Nafru\Email\App\Connection;
use Nafru\Email\App\ConnectionGrant;
use Nafru\Email\Http\CurlTransport;
use Nafru\Email\Http\DeprecationNotice;
use Nafru\Email\Http\Http;
use Nafru\Email\Http\Transport;

/**
 * "Nafru ile bağlan": müşterinin Nafru Email hesabına tek tıkla bağlanır, o hesap adına gönderir. API anahtarı kopyalama yoktur.
 * Tek alan adı/anahtar için `NafruEmail` kullanın.
 *
 * @phpstan-import-type AppScope from \Nafru\Email\Types
 * @phpstan-import-type AuthorizeUrl from \Nafru\Email\Types
 */
final class NafruConnect
{
    private readonly string $web;
    private readonly Http $oauth;
    private readonly Transport $transport;
    private readonly string|false $devOutbox;
    private readonly string $baseUrl;
    private readonly DeprecationNotice $deprecation;

    /**
     * @param string $clientId kayıtlı uygulamanın `app_…` kimliği (değişmez)
     * @param string $clientSecret yalnız sunucunuzda; tarayıcıya ve istemci paketine girmez
     * @param ?string $baseUrl API'nin kök adresi; varsayılan `NafruEmail::DEFAULT_BASE_URL`
     * @param ?string $webUrl izin ekranının (Nafru web uygulaması) kök adresi; verilmezse `baseUrl` sonundaki `/api` atılarak
     * @param string|false|null $devOutbox verilirse `connection(...)->emails->send` gönderim yapmaz, e-postayı klasöre yazar.
     *        Varsayılan (`null`): `NODE_ENV=development` iken `.nafru/emails`; `false` her zaman gerçek gönderim.
     */
    public function __construct(
        private readonly string $clientId,
        #[\SensitiveParameter] private readonly string $clientSecret,
        ?string $baseUrl = null,
        ?string $webUrl = null,
        ?Transport $transport = null,
        private readonly int $maxRetries = 2,
        private readonly float $timeout = 30.0,
        string|false|null $devOutbox = null,
    ) {
        if ($clientId === '') {
            throw new \InvalidArgumentException('Nafru SDK: clientId gerekli');
        }
        if ($clientSecret === '') {
            throw new \InvalidArgumentException('Nafru SDK: clientSecret gerekli');
        }
        $this->baseUrl = $baseUrl ?: NafruEmail::DEFAULT_BASE_URL;
        Http::assertSecureUrl($this->baseUrl, 'baseUrl');
        $this->transport = $transport ?? new CurlTransport();
        $this->deprecation = new DeprecationNotice();
        $this->devOutbox = DevOutbox::resolve($devOutbox);
        // Token uçları kimlik bilgisini gövdede taşır; Authorization başlığı yok.
        $this->oauth = $this->makeHttp(static fn (): ?string => null);
        $this->web = rtrim($webUrl ?? preg_replace('#/api/*$#', '', $this->baseUrl), '/');
        Http::assertSecureUrl($this->web, 'webUrl');
    }

    /** `var_dump`/`print_r` istemci sırrını göstermesin. */
    public function __debugInfo(): array
    {
        return ['clientId' => $this->clientId, 'clientSecret' => '[REDACTED]', 'baseUrl' => $this->baseUrl, 'webUrl' => $this->web];
    }

    /**
     * PKCE (S256): 32 rastgele bayttan 43 karakterlik doğrulayıcı ve SHA-256 sınaması.
     *
     * @return array{verifier: string, challenge: string}
     */
    public static function createPkce(): array
    {
        $verifier = self::base64Url(random_bytes(32));
        return ['verifier' => $verifier, 'challenge' => self::base64Url(hash('sha256', $verifier, true))];
    }

    private static function base64Url(string $bytes): string
    {
        return rtrim(strtr(base64_encode($bytes), '+/', '-_'), '=');
    }

    /**
     * Müşteriyi yönlendireceğiniz "Nafru ile bağlan" adresi. `codeVerifier`'ı oturumda saklayın; dönüşte `exchange`'e verin.
     * Dönüşte `state`'i kendi sakladığınız değerle karşılaştırmak sizin sorumluluğunuzdur.
     *
     * @param string $redirectUri kayıtlı yönlendirme adresiyle birebir aynı olmalı
     * @param string $state CSRF koruması: istekten önce üretip oturumda saklayın, dönüşte karşılaştırın
     * @param list<AppScope> $scopes
     * @param ?string $loginHint müşterinin e-postası biliniyorsa kayıt/giriş ekranında önerilir
     * @return AuthorizeUrl
     */
    public function authorizeUrl(string $redirectUri, string $state, array $scopes, ?string $loginHint = null): array
    {
        if ($state === '') {
            throw new \InvalidArgumentException('Nafru SDK: state gerekli (CSRF koruması)');
        }
        if ($scopes === []) {
            throw new \InvalidArgumentException('Nafru SDK: en az bir izin (scopes) gerekli');
        }
        $pkce = self::createPkce();
        $params = [
            'client_id' => $this->clientId,
            'redirect_uri' => $redirectUri,
            'state' => $state,
            'scope' => implode(' ', $scopes),
            'code_challenge' => $pkce['challenge'],
            'code_challenge_method' => 'S256',
        ];
        if ($loginHint !== null && $loginHint !== '') {
            $params['login_hint'] = $loginHint;
        }
        return ['url' => "{$this->web}/connect?" . http_build_query($params), 'codeVerifier' => $pkce['verifier']];
    }

    /**
     * Dönüşteki tek kullanımlık `code`'u bağlantıya çevirir (sunucunuzdan çağırın).
     *
     */
    public function exchange(#[\SensitiveParameter] string $code, #[\SensitiveParameter] string $codeVerifier, string $redirectUri): ConnectionGrant
    {
        $data = $this->oauth->request('POST', '/oauth/token', body: [
            'grant_type' => 'authorization_code',
            'client_id' => $this->clientId,
            'client_secret' => $this->clientSecret,
            'code' => $code,
            'code_verifier' => $codeVerifier,
            'redirect_uri' => $redirectUri,
        ]);
        return new ConnectionGrant($data['connection_id'], $data['refresh_token'], $data['scopes']);
    }

    /** Bağlantıyı uygulama tarafından iptal eder (müşteri hesabını kapattığında). Belirteçler anında geçersiz olur. */
    public function revoke(#[\SensitiveParameter] string $refreshToken): void
    {
        $this->oauth->request('POST', '/oauth/revoke', body: [
            'client_id' => $this->clientId,
            'client_secret' => $this->clientSecret,
            'token' => $refreshToken,
        ]);
    }

    /**
     * Saklanan yenileme belirteciyle bir müşteri bağlantısı. Yenileme otomatiktir; yeni belirteç `$onTokenRefresh` ile gelir.
     *
     * @param callable(array{refreshToken: string}): void $onTokenRefresh yenileme belirteci döndüğünde çağrılır; yeni değeri KALICI
     *        olarak yazmadan eskisi geçersizdir. Hata fırlatırsa çağrı `token_persist_failed` ile yükselir.
     */
    public function connection(string $connectionId, #[\SensitiveParameter] string $refreshToken, callable $onTokenRefresh): Connection
    {
        return new Connection(
            $connectionId,
            fn (\Closure $authorize): Http => $this->makeHttp($authorize),
            $this->oauth,
            $this->clientId,
            $this->clientSecret,
            $refreshToken,
            $onTokenRefresh(...),
            $this->devOutbox,
        );
    }

    private function makeHttp(\Closure $authorize): Http
    {
        return new Http('', $this->baseUrl, $this->transport, $this->maxRetries, $this->timeout, NafruEmail::USER_AGENT, $authorize, $this->deprecation);
    }
}
