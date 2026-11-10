<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

use Nafru\Email\DevOutbox;
use Nafru\Email\Http\Requester;

/**
 * @phpstan-import-type SendEmailInput from \Nafru\Email\Types
 * @phpstan-import-type BatchEmailItem from \Nafru\Email\Types
 * @phpstan-import-type SendEmailResponse from \Nafru\Email\Types
 * @phpstan-import-type BatchEmailResponse from \Nafru\Email\Types
 * @phpstan-import-type Email from \Nafru\Email\Types
 * @phpstan-import-type EmailListItem from \Nafru\Email\Types
 * @phpstan-import-type ListEmailsQuery from \Nafru\Email\Types
 * @phpstan-import-type EmailRef from \Nafru\Email\Types
 */
final class Emails extends Resource
{
    public function __construct(Requester $http, private readonly string|false $devOutbox = false)
    {
        parent::__construct($http);
    }

    /**
     * `POST /emails`. `scheduled_at` verilirse zamanlanır; `idempotencyKey` ile yineleme güvenlidir.
     *
     * @param SendEmailInput $input
     * @return SendEmailResponse
     */
    public function send(array $input, ?string $idempotencyKey = null): array
    {
        if ($this->devOutbox !== false) {
            return DevOutbox::write($this->devOutbox, $input);
        }
        return $this->http->request('POST', '/emails', body: $input, idempotencyKey: $idempotencyKey);
    }

    /**
     * `POST /emails/batch`: en çok 100 e-posta; ek ve şablon desteklenmez.
     *
     * @param list<BatchEmailItem> $input
     * @return BatchEmailResponse
     */
    public function batch(array $input, ?string $idempotencyKey = null): array
    {
        if ($this->devOutbox === false) {
            return $this->http->request('POST', '/emails/batch', body: $input, idempotencyKey: $idempotencyKey);
        }
        $data = [];
        foreach ($input as $item) {
            $data[] = DevOutbox::write($this->devOutbox, $item);
        }
        return ['data' => $data];
    }

    /** @return Email */
    public function get(string $id): array
    {
        return $this->http->request('GET', '/emails/' . self::seg($id));
    }

    /**
     * @param ListEmailsQuery $query
     * @return array{object: 'list', data: list<EmailListItem>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->http->request('GET', '/emails', $query);
    }

    /**
     * Zamanlanmış e-postanın gönderim anını değiştirir.
     *
     * @param array{scheduled_at: string} $input
     * @return EmailRef
     */
    public function update(string $id, array $input): array
    {
        return $this->http->request('PATCH', '/emails/' . self::seg($id), body: $input);
    }

    /**
     * Zamanlanmış e-postayı iptal eder.
     *
     * @return EmailRef
     */
    public function cancel(string $id): array
    {
        return $this->http->request('POST', '/emails/' . self::seg($id) . '/cancel');
    }
}
