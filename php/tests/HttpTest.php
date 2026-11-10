<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\Http\Response;
use Nafru\Email\Http\TransportException;
use Nafru\Email\NafruEmail;
use Nafru\Email\NafruException;
use PHPUnit\Framework\TestCase;

final class HttpTest extends TestCase
{
    /** @param list<Response|\Closure> $responses */
    private function client(array $responses, int $maxRetries = 0): array
    {
        $transport = new MockTransport($responses);
        return [new NafruEmail('key_test', 'https://api.test/', $transport, $maxRetries, devOutbox: false), $transport];
    }

    private function catch(callable $run): NafruException
    {
        try {
            $run();
        } catch (NafruException $error) {
            return $error;
        }
        self::fail('NafruException bekleniyordu');
    }

    public function testSendsAuthUserAgentJsonAndIdempotencyKey(): void
    {
        [$nafru, $t] = $this->client([Response::json(['id' => 'e1'])]);
        $result = $nafru->emails->send(['from' => 'a@x.test', 'to' => 'b@x.test', 'subject' => 'ş', 'text' => 't'], 'k-1');
        self::assertSame(['id' => 'e1'], $result);
        $call = $t->calls[0];
        self::assertSame('POST', $call['method']);
        self::assertSame('https://api.test/emails', $call['url']);
        self::assertSame('Bearer key_test', $call['headers']['authorization']);
        self::assertSame('application/json', $call['headers']['content-type']);
        self::assertSame('k-1', $call['headers']['idempotency-key']);
        self::assertSame('nafru-email-php/' . NafruEmail::SDK_VERSION, $call['headers']['user-agent']);
        self::assertSame('{"from":"a@x.test","to":"b@x.test","subject":"ş","text":"t"}', $call['body']);
    }

    public function testQuerySkipsEmptyValues(): void
    {
        [$nafru, $t] = $this->client([Response::json(['object' => 'list', 'data' => [], 'has_more' => false])]);
        $nafru->contacts->list(['limit' => 5, 'after' => null, 'before' => '', 'search' => 'ali veli']);
        self::assertSame('https://api.test/contacts?limit=5&search=ali+veli', $t->calls[0]['url']);
    }

    public function testParsesErrorBody(): void
    {
        $body = ['statusCode' => 422, 'name' => 'validation_error', 'message' => 'Geçersiz', 'errors' => [['field' => 'to', 'message' => 'zorunlu', 'i18nTranslationKey' => 'k']]];
        [$nafru] = $this->client([Response::json($body, 422)]);
        $error = $this->catch(fn () => $nafru->emails->send(['to' => 'x', 'text' => 't']));
        self::assertSame(422, $error->statusCode);
        self::assertSame('validation_error', $error->name);
        self::assertSame('Geçersiz', $error->getMessage());
        self::assertSame($body['errors'], $error->errors);
        self::assertNull($error->retryAfter);
    }

    public function testBuildsErrorFromStatusWhenBodyIsNotStandard(): void
    {
        [$nafru] = $this->client([new Response(502, '<html>bad gateway</html>', [], 'Bad Gateway')]);
        $error = $this->catch(fn () => $nafru->emails->get('e1'));
        self::assertSame([502, 'application_error', 'Bad Gateway'], [$error->statusCode, $error->name, $error->getMessage()]);

        [$nafru] = $this->client([new Response(404)]);
        $error = $this->catch(fn () => $nafru->emails->get('e1'));
        self::assertSame([404, 'not_found', 'HTTP 404'], [$error->statusCode, $error->name, $error->getMessage()]);
    }

    public function testNetworkErrorAndTimeoutHaveNullStatus(): void
    {
        [$nafru] = $this->client([fn () => throw new TransportException('bağlantı reddedildi')]);
        $error = $this->catch(fn () => $nafru->emails->send(['to' => 'x', 'text' => 't']));
        self::assertSame([null, 'application_error', 'bağlantı reddedildi'], [$error->statusCode, $error->name, $error->getMessage()]);

        [$nafru] = $this->client([fn () => throw new TransportException('timeout', true)]);
        $error = $this->catch(fn () => $nafru->emails->get('e1'));
        self::assertSame([null, 'timeout_error'], [$error->statusCode, $error->name]);
    }

    public function testRetries429WithRetryAfterEvenForPost(): void
    {
        $limited = Response::json(['statusCode' => 429, 'name' => 'rate_limit_exceeded', 'message' => 'yavaş'], 429, ['Retry-After' => '0']);
        [$nafru, $t] = $this->client([$limited, Response::json(['id' => 'e1'])], 2);
        self::assertSame(['id' => 'e1'], $nafru->emails->send(['to' => 'x', 'text' => 't']));
        self::assertCount(2, $t->calls);
    }

    public function testRateLimitAfterRetriesExposesRetryAfter(): void
    {
        $limited = Response::json(['statusCode' => 429, 'name' => 'rate_limit_exceeded', 'message' => 'yavaş'], 429, ['retry-after' => '0']);
        [$nafru, $t] = $this->client([$limited], 1);
        $error = $this->catch(fn () => $nafru->emails->get('e1'));
        self::assertSame([429, 'rate_limit_exceeded', 0], [$error->statusCode, $error->name, $error->retryAfter]);
        self::assertCount(2, $t->calls);
    }

    public function testGet5xxRetriedButPostWithoutKeyNot(): void
    {
        $down = Response::json(['statusCode' => 500, 'name' => 'application_error', 'message' => 'x'], 500);
        [$nafru, $t] = $this->client([$down, Response::json(['id' => 'e1'])], 1);
        self::assertSame('e1', $nafru->emails->get('e1')['id']);
        self::assertCount(2, $t->calls);

        [$nafru, $t] = $this->client([$down, Response::json(['id' => 'e1'])], 1);
        self::assertSame(500, $this->catch(fn () => $nafru->emails->send(['to' => 'x', 'text' => 't']))->statusCode);
        self::assertCount(1, $t->calls);
    }

    public function testPostWithIdempotencyKeyRetriedAfter5xx(): void
    {
        $down = Response::json(['statusCode' => 503, 'name' => 'application_error', 'message' => 'x'], 503);
        [$nafru, $t] = $this->client([$down, Response::json(['id' => 'e1'])], 1);
        self::assertSame(['id' => 'e1'], $nafru->emails->send(['to' => 'x', 'text' => 't'], 'k-1'));
        self::assertCount(2, $t->calls);
        self::assertSame('k-1', $t->calls[1]['headers']['idempotency-key']);
    }

    public function testApiKeyRequiredAndBaseUrlDefaults(): void
    {
        foreach ([null, ''] as $baseUrl) {
            $t = new MockTransport([Response::json(['id' => 'e1'])]);
            (new NafruEmail('k', $baseUrl, $t, devOutbox: false))->emails->get('e1');
            self::assertSame('https://email.nafru.com/api/emails/e1', $t->calls[0]['url']);
        }
        self::assertSame('https://email.nafru.com/api', NafruEmail::DEFAULT_BASE_URL);
        $previous = getenv('NAFRU_API_KEY');
        putenv('NAFRU_API_KEY');
        try {
            $this->expectExceptionMessage('apiKey');
            new NafruEmail('');
        } finally {
            putenv($previous === false ? 'NAFRU_API_KEY' : "NAFRU_API_KEY=$previous");
        }
    }

    public function testApiKeyFallsBackToEnvironment(): void
    {
        $previous = getenv('NAFRU_API_KEY');
        putenv('NAFRU_API_KEY=nafru_env');
        try {
            $t = new MockTransport([Response::json(['id' => 'e1'])]);
            (new NafruEmail(transport: $t, devOutbox: false))->emails->get('e1');
            self::assertSame('Bearer nafru_env', $t->calls[0]['headers']['authorization']);
        } finally {
            putenv($previous === false ? 'NAFRU_API_KEY' : "NAFRU_API_KEY=$previous");
        }
    }

    public function testHttpsOnlyExceptLoopback(): void
    {
        foreach (['http://localhost:48787/api', 'http://app.localhost/api', 'http://127.0.0.1:8080', 'http://[::1]:1/api', 'https://email.example'] as $url) {
            self::assertInstanceOf(NafruEmail::class, new NafruEmail('k', $url, new MockTransport([])));
        }
        foreach (['http://email.example/api', 'http://localhost.evil.com', 'http://128.0.0.1', 'file:///etc/passwd', 'localhost:48787'] as $url) {
            try {
                new NafruEmail('k', $url, new MockTransport([]));
                self::fail($url);
            } catch (\InvalidArgumentException $e) {
                self::assertStringContainsString('https', $e->getMessage());
            }
        }
    }

    public function testRedirectIsRefusedAndNotRetried(): void
    {
        [$nafru, $t] = $this->client([new Response(302, '', ['location' => 'https://evil.test/'])], 2);
        $error = $this->catch(fn () => $nafru->emails->get('e1'));
        self::assertSame([302, 'unexpected_redirect'], [$error->statusCode, $error->name]);
        self::assertCount(1, $t->calls);
    }

    public function testRejectsDotSegmentsAndUnsafeIdempotencyKeys(): void
    {
        [$nafru, $t] = $this->client([Response::json(['id' => 'e1'])]);
        foreach (['', '.', '..'] as $id) {
            self::assertSame('invalid_argument', $this->catch(fn () => $nafru->contacts->get($id))->name);
        }
        self::assertSame('invalid_argument', $this->catch(fn () => $nafru->contacts->segments->add('c1', '..'))->name);
        foreach (['', "k\r\nX-Evil: 1", "k\n", "k\x00"] as $key) {
            self::assertSame('invalid_argument', $this->catch(fn () => $nafru->emails->send(['to' => 'x'], $key))->name);
        }
        self::assertSame([], $t->calls);
        $nafru->contacts->get('..a'); // yalnız tam `.`/`..` reddedilir
        self::assertSame('https://api.test/contacts/..a', $t->calls[0]['url']);
    }

    public function testResponseTooLarge(): void
    {
        [$nafru] = $this->client([new Response(200, str_repeat('x', 10 * 1024 * 1024 + 1))]);
        self::assertSame('response_too_large', $this->catch(fn () => $nafru->emails->get('e1'))->name);
    }

    public function testClientDebugOutputHidesApiKey(): void
    {
        [$nafru] = $this->client([]);
        $dump = print_r($nafru, true);
        ob_start();
        var_dump($nafru);
        $dump .= ob_get_clean();
        self::assertStringNotContainsString('key_test', $dump);
        self::assertStringContainsString('[REDACTED]', $dump);
    }

    public function testDeprecationHeaderWarnsOncePerClientAndNeverFails(): void
    {
        $log = tempnam(sys_get_temp_dir(), 'nafru-log-');
        $previous = ini_set('error_log', $log);
        try {
            $deprecated = ['deprecation' => 'true', 'sunset' => 'Wed, 01 Jul 2026 00:00:00 GMT', 'link' => '<https://nafru.com/sdk>; rel="deprecation"'];
            [$nafru] = $this->client([
                Response::json(['id' => 'e1'], 200, $deprecated),
                Response::json(['statusCode' => 404, 'name' => 'not_found', 'message' => 'yok'], 404, $deprecated),
            ]);
            self::assertSame(['id' => 'e1'], $nafru->emails->get('e1'));
            self::assertSame('not_found', $this->catch(fn () => $nafru->emails->get('e2'))->name);
            $text = (string) file_get_contents($log);
            self::assertSame(1, substr_count($text, '[nafru] Bu SDK sürümü (php ' . NafruEmail::SDK_VERSION . ') kullanımdan kaldırıldı; lütfen güncelleyin. Son tarih: Wed, 01 Jul 2026 00:00:00 GMT Ayrıntı: https://nafru.com/sdk'));
        } finally {
            ini_set('error_log', (string) $previous);
            unlink($log);
        }
    }
}
