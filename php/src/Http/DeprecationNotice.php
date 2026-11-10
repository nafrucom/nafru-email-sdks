<?php

declare(strict_types=1);

namespace Nafru\Email\Http;

use Nafru\Email\NafruEmail;

/**
 * Sunucu `Deprecation` başlığı gönderirse istemci örneği başına BİR uyarı yazar (`error_log`); çağrıyı asla bozmaz.
 *
 * @internal
 */
final class DeprecationNotice
{
    private bool $warned = false;

    public function check(Response $response): void
    {
        if ($this->warned || !isset($response->headers['deprecation'])) {
            return;
        }
        $this->warned = true;
        $message = '[nafru] Bu SDK sürümü (php ' . NafruEmail::SDK_VERSION . ') kullanımdan kaldırıldı; lütfen güncelleyin.';
        if (($sunset = $response->headers['sunset'] ?? '') !== '') {
            $message .= " Son tarih: $sunset";
        }
        if (($link = $response->headers['link'] ?? '') !== '') {
            $message .= ' Ayrıntı: ' . (preg_match('/<([^>]*)>/', $link, $match) ? $match[1] : $link);
        }
        error_log($message);
    }
}
