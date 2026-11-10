<?php

declare(strict_types=1);

namespace Nafru\Email\App;

use Nafru\Email\Resources\Emails;

/**
 * Bağlantı adına e-posta: yalnız `send`, `get`, `list`.
 *
 * @phpstan-import-type SendEmailInput from \Nafru\Email\Types
 * @phpstan-import-type SendEmailResponse from \Nafru\Email\Types
 * @phpstan-import-type Email from \Nafru\Email\Types
 * @phpstan-import-type EmailListItem from \Nafru\Email\Types
 * @phpstan-import-type ListEmailsQuery from \Nafru\Email\Types
 */
final class ConnectionEmails
{
    /** @internal */
    public function __construct(private readonly Emails $emails)
    {
    }

    /**
     * @param SendEmailInput $input
     * @return SendEmailResponse
     */
    public function send(array $input, ?string $idempotencyKey = null): array
    {
        return $this->emails->send($input, $idempotencyKey);
    }

    /** @return Email */
    public function get(string $id): array
    {
        return $this->emails->get($id);
    }

    /**
     * @param ListEmailsQuery $query
     * @return array{object: 'list', data: list<EmailListItem>, has_more: bool}
     */
    public function list(array $query = []): array
    {
        return $this->emails->list($query);
    }
}
