<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\Http\Response;
use Nafru\Email\NafruConnect;
use Nafru\Email\NafruException;
use PHPUnit\Framework\TestCase;

final class AppTest extends TestCase
{
    private static function server(\Closure $route): array
    {
        $t = new MockTransport($route);
        return [new NafruConnect('app_x', 'nfs_secret', 'https://api.test/', 'https://web.test', $t, 0, devOutbox: false), $t];
    }

    private static function token(int $n): Response
    {
        return Response::json(['access_token' => "nfa_$n", 'refresh_token' => "nfr_$n", 'token_type' => 'Bearer', 'expires_in' => 3600, 'connection_id' => 'conn_1', 'scopes' => ['emails.send']]);
    }

    private static function isToken(array $call): bool
    {
        return str_ends_with($call['url'], '/oauth/token');
    }

    private static function api(MockTransport $t): array
    {
        return array_values(array_filter($t->calls, fn ($c) => !str_contains($c['url'], '/oauth/')));
    }

    private static function catch(callable $run): NafruException
    {
        try {
            $run();
        } catch (NafruException $error) {
            return $error;
        }
        self::fail('NafruException bekleniyordu');
    }

    public function testPkce(): void
    {
        $pkce = NafruConnect::createPkce();
        self::assertMatchesRegularExpression('/^[A-Za-z0-9_-]{43}$/', $pkce['verifier']);
        self::assertSame(rtrim(strtr(base64_encode(hash('sha256', $pkce['verifier'], true)), '+/', '-_'), '='), $pkce['challenge']);
        self::assertNotSame($pkce['verifier'], NafruConnect::createPkce()['verifier']);
    }

    public function testAuthorizeUrl(): void
    {
        [$nafru] = self::server(fn () => Response::json([]));
        $result = $nafru->authorizeUrl('https://scout.test/cb', 'st1', ['emails.send', 'templates.read'], 'a@b.co');
        $parts = parse_url($result['url']);
        self::assertSame('https://web.test/connect', "{$parts['scheme']}://{$parts['host']}{$parts['path']}");
        parse_str($parts['query'], $query);
        self::assertSame('app_x', $query['client_id']);
        self::assertSame('https://scout.test/cb', $query['redirect_uri']);
        self::assertSame('st1', $query['state']);
        self::assertSame('emails.send templates.read', $query['scope']);
        self::assertSame('S256', $query['code_challenge_method']);
        self::assertSame('a@b.co', $query['login_hint']);
        self::assertSame(rtrim(strtr(base64_encode(hash('sha256', $result['codeVerifier'], true)), '+/', '-_'), '='), $query['code_challenge']);

        foreach ([['x', '', ['emails.send']], ['x', 's', []]] as $args) {
            try {
                $nafru->authorizeUrl(...$args);
                self::fail();
            } catch (\InvalidArgumentException) {
                self::addToAssertionCount(1);
            }
        }
    }

    public function testWebUrlDefaultsToBaseUrlWithoutApi(): void
    {
        $nafru = new NafruConnect('app_x', 's', 'https://email.nafru.test/api/', transport: new MockTransport([]));
        self::assertStringStartsWith('https://email.nafru.test/connect?', $nafru->authorizeUrl('r', 's', ['emails.send'])['url']);
    }

    public function testBaseUrlDefaultsAndWebUrlDerivesFromIt(): void
    {
        $t = new MockTransport([self::token(1)]);
        $nafru = new NafruConnect('app_x', 's', transport: $t);
        self::assertStringStartsWith('https://email.nafru.com/connect?', $nafru->authorizeUrl('r', 's', ['emails.send'])['url']);
        $nafru->exchange('c', 'v', 'r');
        self::assertSame('https://email.nafru.com/api/oauth/token', $t->calls[0]['url']);
    }

    public function testSecretsAreRedactedFromDebugOutput(): void
    {
        [$nafru, $t] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json(['ready' => true]));
        $grant = $nafru->exchange('nfc_1', 'v', 'r');
        $connection = $nafru->connection('conn_1', 'nfr_0', fn () => null);
        $connection->status();
        $dump = print_r($nafru, true) . print_r($grant, true) . print_r($connection, true);
        ob_start();
        var_dump($nafru, $grant, $connection);
        $dump .= ob_get_clean();
        foreach (['nfs_secret', 'nfr_1', 'nfr_0', 'nfa_1'] as $secret) {
            self::assertStringNotContainsString($secret, $dump);
        }
        self::assertStringContainsString('[REDACTED]', $dump);
        self::assertStringContainsString('conn_1', $dump);
    }

    public function testRejectsInsecureUrls(): void
    {
        foreach (['http://email.nafru.test/api', 'ftp://x.test'] as $url) {
            try {
                new NafruConnect('app_x', 's', $url, transport: new MockTransport([]));
                self::fail($url);
            } catch (\InvalidArgumentException $e) {
                self::assertStringContainsString('baseUrl https', $e->getMessage());
            }
        }
        try {
            new NafruConnect('app_x', 's', 'https://email.nafru.test/api', 'http://web.example', new MockTransport([]));
            self::fail();
        } catch (\InvalidArgumentException $e) {
            self::assertStringContainsString('webUrl https', $e->getMessage());
        }
    }

    public function testExchangeAndRevokeSendNoAuthorizationHeader(): void
    {
        [$nafru, $t] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json([]));
        $grant = $nafru->exchange('nfc_1', str_repeat('v', 43), 'https://scout.test/cb');
        self::assertSame(['conn_1', 'nfr_1', ['emails.send']], [$grant->connectionId, $grant->refreshToken, $grant->scopes]);
        $nafru->revoke('nfr_1');
        self::assertSame('https://api.test/oauth/token', $t->calls[0]['url']);
        self::assertArrayNotHasKey('authorization', $t->calls[0]['headers']);
        self::assertSame(['grant_type' => 'authorization_code', 'client_id' => 'app_x', 'client_secret' => 'nfs_secret', 'code' => 'nfc_1', 'code_verifier' => str_repeat('v', 43), 'redirect_uri' => 'https://scout.test/cb'], $t->calls[0]['json']);
        self::assertSame(['client_id' => 'app_x', 'client_secret' => 'nfs_secret', 'token' => 'nfr_1'], $t->calls[1]['json']);
        self::assertArrayNotHasKey('authorization', $t->calls[1]['headers']);
    }

    public function testRefreshesOnceRotatesAndReusesToken(): void
    {
        [$nafru, $t] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json(['ready' => true]));
        $saved = [];
        $connection = $nafru->connection('conn_1', 'nfr_0', function (array $tokens) use (&$saved): void {
            $saved[] = $tokens['refreshToken'];
        });
        for ($i = 0; $i < 5; $i++) {
            self::assertSame(['ready' => true], $connection->status());
        }
        self::assertCount(1, array_filter($t->calls, self::isToken(...)));
        self::assertSame(['grant_type' => 'refresh_token', 'client_id' => 'app_x', 'client_secret' => 'nfs_secret', 'refresh_token' => 'nfr_0'], $t->calls[0]['json']);
        self::assertSame(['nfr_1'], $saved);
        self::assertSame('https://api.test/connection', self::api($t)[0]['url']);
        self::assertSame(['Bearer nfa_1'], array_unique(array_map(fn ($c) => $c['headers']['authorization'], self::api($t))));
    }

    public function testInvalidTokenRefreshesOnceAndRetriesWithRotatedRefreshToken(): void
    {
        $refreshes = 0;
        [$nafru, $t] = self::server(function ($c) use (&$refreshes) {
            if (self::isToken($c)) {
                return self::token(++$refreshes);
            }
            return $c['headers']['authorization'] === 'Bearer nfa_1'
                ? Response::json(['statusCode' => 401, 'name' => 'invalid_token', 'message' => 'expired'], 401)
                : Response::json(['ready' => true]);
        });
        $connection = $nafru->connection('conn_1', 'nfr_0', fn () => null);
        self::assertSame(['ready' => true], $connection->status());
        self::assertSame(2, $refreshes);
        self::assertSame(['Bearer nfa_1', 'Bearer nfa_2'], array_map(fn ($c) => $c['headers']['authorization'], self::api($t)));
        $tokenCalls = array_values(array_filter($t->calls, self::isToken(...)));
        self::assertSame('nfr_1', $tokenCalls[1]['json']['refresh_token']);
    }

    public function testRejectedRefreshBecomesConnectionRevoked(): void
    {
        [$nafru, $t] = self::server(fn () => Response::json(['statusCode' => 400, 'name' => 'invalid_grant', 'message' => 'invalid'], 400));
        $error = self::catch(fn () => $nafru->connection('conn_1', 'nfr_0', fn () => null)->status());
        self::assertSame(['connection_revoked', 400], [$error->name, $error->statusCode]);
        self::assertSame([], self::api($t));

        [$nafru] = self::server(fn () => Response::json(['statusCode' => 403, 'name' => 'forbidden', 'message' => 'x'], 403));
        self::assertSame('connection_revoked', self::catch(fn () => $nafru->connection('c', 'r', fn () => null)->status())->name);
    }

    public function testPersistFailureIsReportedAndRetriedWithoutNewRefresh(): void
    {
        [$nafru, $t] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json(['ready' => true]));
        $saved = [];
        $failures = 1;
        $connection = $nafru->connection('conn_1', 'nfr_0', function (array $tokens) use (&$saved, &$failures): void {
            if ($failures-- > 0) {
                throw new \RuntimeException('disk dolu');
            }
            $saved[] = $tokens['refreshToken'];
        });
        $error = self::catch(fn () => $connection->status());
        self::assertSame('token_persist_failed', $error->name);
        self::assertStringContainsString('disk dolu', $error->getMessage());
        self::assertSame(['ready' => true], $connection->status());
        self::assertSame(['nfr_1'], $saved);
        self::assertCount(1, array_filter($t->calls, self::isToken(...)));
    }

    public function testConnectionEndpoints(): void
    {
        [$nafru, $t] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json(['id' => 'e1', 'data' => []]));
        $connection = $nafru->connection('conn_1', 'nfr_0', fn () => null);
        self::assertSame('conn_1', $connection->id);
        $connection->senders();
        $connection->templates();
        $connection->emails->send(['from' => 'a@b.co', 'to' => ['c@d.co'], 'subject' => 's', 'html' => '<p>x</p>'], 'k1');
        $connection->emails->get('e1');
        $connection->emails->list();
        self::assertSame(
            ['GET /senders', 'GET /templates', 'POST /emails', 'GET /emails/e1', 'GET /emails'],
            array_map(fn ($c) => $c['method'] . ' ' . parse_url($c['url'], PHP_URL_PATH), self::api($t)),
        );
        self::assertSame('k1', self::api($t)[2]['headers']['idempotency-key']);

        [$nafru] = self::server(fn ($c) => self::isToken($c) ? self::token(1) : Response::json(['statusCode' => 403, 'name' => 'insufficient_scope', 'message' => 'scope'], 403));
        $error = self::catch(fn () => $nafru->connection('c', 'r', fn () => null)->templates());
        self::assertSame([403, 'insufficient_scope'], [$error->statusCode, $error->name]);
    }
}
