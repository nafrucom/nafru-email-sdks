<?php

declare(strict_types=1);

namespace Nafru\Email;

use Nafru\Email\Http\Response;

/**
 * Her başarısız çağrı bunu fırlatır. `statusCode` ağ hatalarında `null`'dır. `name`, sunucunun hata adıdır
 * (`validation_error`, `rate_limit_exceeded`, `not_found`, …); ağ ve zaman aşımı için `application_error` / `timeout_error`.
 */
class NafruException extends \RuntimeException
{
    private const NAMES_BY_STATUS = [
        400 => 'invalid_request',
        401 => 'unauthorized',
        403 => 'forbidden',
        404 => 'not_found',
        409 => 'conflict',
        413 => 'payload_too_large',
        422 => 'validation_error',
        429 => 'rate_limit_exceeded',
    ];

    /**
     * @param list<array{field: string, message: string, i18nTranslationKey?: string}> $errors 422'de alan ayrıntısı
     * @param int|float|null $retryAfter `429` yanıtındaki `retry-after` (saniye)
     */
    public function __construct(
        public readonly ?int $statusCode,
        public readonly string $name,
        string $message,
        public readonly array $errors = [],
        public readonly int|float|null $retryAfter = null,
        ?\Throwable $previous = null,
    ) {
        parent::__construct($message, $statusCode ?? 0, $previous);
    }

    public static function network(string $message, ?\Throwable $previous = null): self
    {
        return new self(null, 'application_error', $message, previous: $previous);
    }

    public static function timeout(float $timeoutSeconds): self
    {
        return new self(null, 'timeout_error', sprintf('İstek %d ms içinde tamamlanmadı', (int) round($timeoutSeconds * 1000)));
    }

    /** Aynı alanlarla yeni ad/ileti (ör. `connection_revoked`). */
    public function withName(string $name, string $message): self
    {
        return new self($this->statusCode, $name, $message, $this->errors, $this->retryAfter, $this);
    }

    /** Standart gövde (`statusCode`, `name`, `message`, `errors`) yoksa durumdan makul bir hata kurar (ara katman HTML'i, boş gövde). */
    public static function fromResponse(Response $response, mixed $body): self
    {
        $status = $response->status;
        $raw = $response->headers['retry-after'] ?? null;
        $retryAfter = $raw !== null && is_numeric(trim($raw)) && (float) $raw >= 0 ? 0 + trim($raw) : null;
        $fallbackName = self::NAMES_BY_STATUS[$status] ?? 'application_error';

        if (is_array($body) && !array_is_list($body) && is_string($body['message'] ?? null)) {
            $errors = [];
            foreach (is_array($body['errors'] ?? null) ? $body['errors'] : [] as $entry) {
                if (!is_array($entry) || array_is_list($entry) && $entry !== []) {
                    continue;
                }
                $error = [
                    'field' => is_string($entry['field'] ?? null) ? $entry['field'] : '',
                    'message' => is_string($entry['message'] ?? null) ? $entry['message'] : '',
                ];
                if (is_string($entry['i18nTranslationKey'] ?? null)) {
                    $error['i18nTranslationKey'] = $entry['i18nTranslationKey'];
                }
                $errors[] = $error;
            }
            return new self(
                is_int($body['statusCode'] ?? null) ? $body['statusCode'] : $status,
                is_string($body['name'] ?? null) ? $body['name'] : $fallbackName,
                $body['message'],
                $errors,
                $retryAfter,
            );
        }

        return new self($status, $fallbackName, $response->reasonPhrase !== '' ? $response->reasonPhrase : "HTTP $status", [], $retryAfter);
    }
}
