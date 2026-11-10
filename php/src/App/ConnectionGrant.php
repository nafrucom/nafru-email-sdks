<?php

declare(strict_types=1);

namespace Nafru\Email\App;

/**
 * `NafruConnect::exchange` sonucu. Yenileme belirteci `var_dump`/`print_r` çıktısında gizlenir.
 *
 * @phpstan-import-type AppScope from \Nafru\Email\Types
 */
final class ConnectionGrant
{
    /**
     * @param string $connectionId `conn_…`: müşteri bağlantısının kalıcı kimliği (kendi veritabanınızda müşteriyle eşleyin)
     * @param string $refreshToken şifreleyerek saklayın; tarayıcıya vermeyin. Her yenilemede değişir (`onTokenRefresh`)
     * @param list<AppScope> $scopes
     */
    public function __construct(
        public readonly string $connectionId,
        #[\SensitiveParameter] public readonly string $refreshToken,
        public readonly array $scopes,
    ) {
    }

    public function __debugInfo(): array
    {
        return ['connectionId' => $this->connectionId, 'refreshToken' => '[REDACTED]', 'scopes' => $this->scopes];
    }
}
