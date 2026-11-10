<?php

declare(strict_types=1);

namespace Nafru\Email;

use Nafru\Email\Http\CurlTransport;
use Nafru\Email\Http\Http;
use Nafru\Email\Http\Transport;
use Nafru\Email\Resources\ApiKeys;
use Nafru\Email\Resources\BrandResource;
use Nafru\Email\Resources\Broadcasts;
use Nafru\Email\Resources\ContactProperties;
use Nafru\Email\Resources\Contacts;
use Nafru\Email\Resources\Domains;
use Nafru\Email\Resources\Emails;
use Nafru\Email\Resources\Events;
use Nafru\Email\Resources\Segments;
use Nafru\Email\Resources\Templates;
use Nafru\Email\Resources\Topics;
use Nafru\Email\Resources\Webhooks;

/** API anahtarlı istemci. Tek alan adı/anahtar içindir; müşteri hesapları adına göndermek için `NafruConnect`. */
final class NafruEmail
{
    public const SDK_VERSION = '0.1.1';
    /** Nafru Email üretim API'si; `baseUrl` verilmezse (ya da boşsa) kullanılır. */
    public const DEFAULT_BASE_URL = 'https://email.nafru.com/api';
    public const USER_AGENT = 'nafru-email-php/' . self::SDK_VERSION;

    public readonly Emails $emails;
    public readonly Domains $domains;
    public readonly Contacts $contacts;
    public readonly ContactProperties $contactProperties;
    public readonly Segments $segments;
    public readonly Topics $topics;
    public readonly Broadcasts $broadcasts;
    public readonly Templates $templates;
    public readonly BrandResource $brand;
    public readonly Webhooks $webhooks;
    public readonly ApiKeys $apiKeys;
    public readonly Events $events;

    /**
     * @param ?string $apiKey Dashboard'dan üretilen API anahtarı; verilmezse ya da boşsa `NAFRU_API_KEY` ortam değişkeni. Yalnız sunucuda kullanın; `sending_access` anahtarı bile e-posta gönderebilir.
     * @param ?string $baseUrl API'nin kök adresi; varsayılan `DEFAULT_BASE_URL` (yerelde `http://localhost:48787/api`).
     * @param ?Transport $transport özel HTTP taşıyıcısı (test, proxy); varsayılan ext-curl
     * @param int $maxRetries `429` ve güvenli isteklerde sunucu/ağ hatası için yeniden deneme sayısı; `0` kapatır
     * @param float $timeout istek başına zaman aşımı (saniye)
     * @param string|false|null $devOutbox verilirse `emails->send`/`batch` gönderim yapmaz, e-postayı bu klasöre `.txt` + `.html` yazar.
     *        Varsayılan (`null`): `NODE_ENV=development` iken `.nafru/emails`, aksi hâlde kapalı; `false` her zaman gerçek gönderim.
     */
    public function __construct(
        #[\SensitiveParameter] ?string $apiKey = null,
        ?string $baseUrl = null,
        ?Transport $transport = null,
        int $maxRetries = 2,
        float $timeout = 30.0,
        string|false|null $devOutbox = null,
    ) {
        $apiKey = $apiKey ?: (string) getenv('NAFRU_API_KEY');
        if ($apiKey === '') {
            throw new \InvalidArgumentException('Nafru SDK: apiKey gerekli');
        }
        $baseUrl = $baseUrl ?: self::DEFAULT_BASE_URL;
        Http::assertSecureUrl($baseUrl, 'baseUrl');
        $http = new Http($apiKey, $baseUrl, $transport ?? new CurlTransport(), $maxRetries, $timeout, self::USER_AGENT);

        $this->emails = new Emails($http, DevOutbox::resolve($devOutbox));
        $this->domains = new Domains($http);
        $this->contacts = new Contacts($http);
        $this->contactProperties = new ContactProperties($http);
        $this->segments = new Segments($http);
        $this->topics = new Topics($http);
        $this->broadcasts = new Broadcasts($http);
        $this->templates = new Templates($http);
        $this->brand = new BrandResource($http);
        $this->webhooks = new Webhooks($http);
        $this->apiKeys = new ApiKeys($http);
        $this->events = new Events($http);
    }
}
