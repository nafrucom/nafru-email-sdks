<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\Webhook;
use PHPUnit\Framework\TestCase;

final class WebhookTest extends TestCase
{
    private static function vector(): array
    {
        return json_decode((string) file_get_contents(__DIR__ . '/../../webhook-test-vector.json'), true, 512, JSON_THROW_ON_ERROR);
    }

    private static function verify(array $v, ?string $payload = null, ?string $signature = null, ?int $now = null, ?string $secret = null): bool
    {
        return Webhook::verify(
            $payload ?? $v['payload'],
            ['id' => $v['id'], 'timestamp' => $v['timestamp'], 'signature' => $signature ?? $v['signature']],
            $secret ?? $v['secret'],
            nowSeconds: $now ?? $v['now_seconds'],
        );
    }

    public function testSharedVector(): void
    {
        $v = self::vector();
        self::assertTrue(self::verify($v));
        self::assertFalse(self::verify($v, payload: $v['payload'] . ' '));
    }

    public function testOneOfMultipleSignaturesIsEnough(): void
    {
        $v = self::vector();
        self::assertTrue(self::verify($v, signature: "v1,bozuk {$v['signature']} v2,x"));
        self::assertFalse(self::verify($v, signature: 'v1,bozuk v2,x'));
    }

    public function testMissingHeadersReturnFalse(): void
    {
        $v = self::vector();
        self::assertFalse(Webhook::verify($v['payload'], [], $v['secret'], nowSeconds: $v['now_seconds']));
        self::assertFalse(Webhook::verify($v['payload'], ['id' => '', 'timestamp' => '', 'signature' => ''], $v['secret'], nowSeconds: $v['now_seconds']));
        self::assertFalse(self::verify($v, signature: ''));
    }

    public function testSignatureListIsBoundedTo32Entries(): void
    {
        $v = self::vector();
        self::assertTrue(self::verify($v, signature: str_repeat('v1,eA== ', 31) . $v['signature']));
        self::assertFalse(self::verify($v, signature: str_repeat('v1,eA== ', 32) . $v['signature']));
    }

    public function testRejectsStaleTimestamp(): void
    {
        $v = self::vector();
        self::assertFalse(self::verify($v, now: $v['now_seconds'] + 301));
        self::assertFalse(self::verify($v, now: $v['now_seconds'] - 301));
        self::assertTrue(self::verify($v, now: $v['now_seconds'] - 300));
    }

    public function testBadSecretThrows(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        self::verify(self::vector(), secret: 'bozuk');
    }

    public function testUndecodableSecretThrows(): void
    {
        $this->expectException(\InvalidArgumentException::class);
        self::verify(self::vector(), secret: 'whsec_!!!');
    }
}
