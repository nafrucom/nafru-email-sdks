<?php

declare(strict_types=1);

namespace Nafru\Email;

/** @internal */
final class DevOutbox
{
    /** `devOutbox` verilmezse: yalnız `NODE_ENV=development` iken `.nafru/emails`; aksi hâlde gerçek gönderim. */
    public static function resolve(string|false|null $devOutbox): string|false
    {
        if ($devOutbox !== null) {
            return $devOutbox;
        }
        return getenv('NODE_ENV') === 'development' ? '.nafru/emails' : false;
    }

    /**
     * E-postayı göndermeden `$dir` altına `.txt` ve `.html` olarak yazar, yolu ve düz metni günlüğe (`error_log`) basar.
     *
     * @param array<string, mixed> $email
     * @return array{id: string}
     */
    public static function write(string $dir, array $email): array
    {
        $now = microtime(true);
        $id = 'dev_' . base_convert((string) (int) ($now * 1000), 10, 36) . substr(base_convert(bin2hex(random_bytes(6)), 16, 36), 0, 6);
        $stamp = str_replace([':', '.'], '-', gmdate('Y-m-d\TH:i:s', (int) $now) . sprintf('.%03dZ', (int) (fmod($now, 1) * 1000)));
        if (!is_dir($dir) && !mkdir($dir, 0777, true) && !is_dir($dir)) {
            throw new \RuntimeException("Dev çıkış kutusu oluşturulamadı: $dir");
        }
        $base = (realpath($dir) ?: $dir) . DIRECTORY_SEPARATOR . "$stamp-$id";

        $list = static fn (mixed $value): string => is_array($value) ? implode(', ', $value) : (string) ($value ?? '');
        $headers = array_filter([
            'From: ' . ($email['from'] ?? ''),
            'To: ' . $list($email['to'] ?? ''),
            !empty($email['cc']) ? 'Cc: ' . $list($email['cc']) : null,
            !empty($email['bcc']) ? 'Bcc: ' . $list($email['bcc']) : null,
            !empty($email['reply_to']) ? 'Reply-To: ' . $list($email['reply_to']) : null,
            'Subject: ' . ($email['subject'] ?? ''),
            !empty($email['scheduled_at']) ? 'Scheduled-At: ' . $email['scheduled_at'] : null,
        ], static fn ($line) => $line !== null);
        $body = self::bodyText($email);
        $text = implode("\n", $headers) . "\n\n$body\n";
        $html = !empty($email['html']) ? $email['html'] : '<pre>' . htmlspecialchars($body, ENT_COMPAT) . '</pre>';

        file_put_contents("$base.txt", $text);
        file_put_contents("$base.html", $html);
        // stdout yerine günlük: web isteğinde yanıt gövdesine karışmasın.
        error_log("[nafru] dev: e-posta gönderilmedi\n  $base.txt\n  $base.html\n\n$text");
        return ['id' => $id];
    }

    /** @param array<string, mixed> $email */
    private static function bodyText(array $email): string
    {
        if (!empty($email['text'])) {
            return $email['text'];
        }
        if (!empty($email['html'])) {
            return self::htmlToText($email['html']);
        }
        if (!empty($email['template'])) {
            $variables = $email['template']['variables'] ?? [];
            return "[şablon {$email['template']['id']}]\n" . json_encode($variables === [] ? new \stdClass() : $variables, JSON_PRETTY_PRINT | JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES);
        }
        return '';
    }

    // shortcut: kaba HTML→metin dönüşümü (etiket silme); yalnız dev önizlemesi için, gerçek gönderime girmez.
    private static function htmlToText(string $html): string
    {
        $text = preg_replace('#<(style|script)[\s\S]*?</\1>#i', '', $html);
        $text = preg_replace('#<br\s*/?>|</(p|div|h[1-6]|li|tr)>#i', "\n", $text);
        $text = preg_replace('#<[^>]+>#', '', $text);
        $text = str_replace(['&nbsp;', '&lt;', '&gt;', '&quot;', '&amp;'], [' ', '<', '>', '"', '&'], $text);
        return trim(preg_replace("#\n{3,}#", "\n\n", $text));
    }
}
