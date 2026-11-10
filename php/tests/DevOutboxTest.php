<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\DevOutbox;
use Nafru\Email\NafruEmail;
use PHPUnit\Framework\TestCase;

final class DevOutboxTest extends TestCase
{
    private string $dir;
    private string $log;

    protected function setUp(): void
    {
        $this->dir = sys_get_temp_dir() . '/nafru-outbox-' . bin2hex(random_bytes(4));
        $this->log = (string) tempnam(sys_get_temp_dir(), 'nafru-log-');
    }

    protected function tearDown(): void
    {
        ini_restore('error_log');
        array_map('unlink', glob("{$this->dir}/*") ?: []);
        @rmdir($this->dir);
        @unlink($this->log);
    }

    public function testWritesFilesInsteadOfSending(): void
    {
        // PHPUnit error_log'u test gövdesinden önce kendine yönlendirir; burada geri alıyoruz.
        ini_set('error_log', $this->log);
        $transport = new MockTransport(fn () => throw new \LogicException('taşıyıcı çağrılmamalı'));
        $nafru = new NafruEmail('k', 'https://api.test', $transport, devOutbox: $this->dir);

        $sent = $nafru->emails->send(['from' => 'a@x.com', 'to' => ['b@y.com', 'c@y.com'], 'subject' => 'Merhaba', 'html' => '<p>Selam <b>Ali</b></p><p>&amp; hoş geldin</p>']);
        $batch = $nafru->emails->batch([['from' => 'a@x.com', 'to' => 'd@y.com', 'subject' => 'S', 'text' => 'düz']]);

        self::assertStringStartsWith('dev_', $sent['id']);
        self::assertCount(1, $batch['data']);
        self::assertCount(2, glob("{$this->dir}/*.txt"));
        self::assertCount(2, glob("{$this->dir}/*.html"));
        [$txt] = glob("{$this->dir}/*-{$sent['id']}.txt");
        $text = file_get_contents($txt);
        self::assertStringContainsString('To: b@y.com, c@y.com', $text);
        self::assertStringContainsString('Subject: Merhaba', $text);
        self::assertStringContainsString("Selam Ali\n& hoş geldin", $text);
        self::assertStringContainsString('<b>Ali</b>', file_get_contents(substr($txt, 0, -4) . '.html'));
        self::assertStringContainsString($txt, file_get_contents($this->log));
        self::assertSame([], $transport->calls);
    }

    public function testDefaultOnlyWhenNodeEnvIsDevelopment(): void
    {
        $previous = getenv('NODE_ENV');
        try {
            putenv('NODE_ENV=development');
            self::assertSame('.nafru/emails', DevOutbox::resolve(null));
            self::assertFalse(DevOutbox::resolve(false));
            putenv('NODE_ENV=production');
            self::assertFalse(DevOutbox::resolve(null));
        } finally {
            putenv($previous === false ? 'NODE_ENV' : "NODE_ENV=$previous");
        }
    }
}
