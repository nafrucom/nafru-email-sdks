<?php

declare(strict_types=1);

namespace Nafru\Email\Tests;

use Nafru\Email\Http\Response;
use Nafru\Email\NafruEmail;
use Nafru\Email\Pagination;
use Nafru\Email\NafruException;
use PHPUnit\Framework\Attributes\DataProvider;
use PHPUnit\Framework\TestCase;

/** Her kaynak çağrısının yöntem + yol + gövde eşlemesi. */
final class ResourcesTest extends TestCase
{
    public static function cases(): array
    {
        $batch = [['from' => 'a@x.test', 'to' => 'b@x.test', 'subject' => 's', 'text' => 't']];
        return [
            'emails.batch' => [fn (NafruEmail $n) => $n->emails->batch($batch), 'POST', '/emails/batch', $batch],
            'emails.get' => [fn (NafruEmail $n) => $n->emails->get('e 1'), 'GET', '/emails/e%201'],
            'emails.list' => [fn (NafruEmail $n) => $n->emails->list(['limit' => 2, 'status' => 'sent']), 'GET', '/emails?limit=2&status=sent'],
            'emails.update' => [fn (NafruEmail $n) => $n->emails->update('e1', ['scheduled_at' => 'in 1 hour']), 'PATCH', '/emails/e1', ['scheduled_at' => 'in 1 hour']],
            'emails.cancel' => [fn (NafruEmail $n) => $n->emails->cancel('e1'), 'POST', '/emails/e1/cancel'],
            'domains.create' => [fn (NafruEmail $n) => $n->domains->create(['name' => 'x.test']), 'POST', '/domains', ['name' => 'x.test']],
            'domains.verify' => [fn (NafruEmail $n) => $n->domains->verify('d1'), 'POST', '/domains/d1/verify'],
            'domains.remove' => [fn (NafruEmail $n) => $n->domains->remove('d1'), 'DELETE', '/domains/d1'],
            'contacts.get e-posta' => [fn (NafruEmail $n) => $n->contacts->get('a+b@x.test'), 'GET', '/contacts/a%2Bb%40x.test'],
            'contacts.update' => [fn (NafruEmail $n) => $n->contacts->update('c1', ['unsubscribed' => true]), 'PATCH', '/contacts/c1', ['unsubscribed' => true]],
            'contacts.segments.add' => [fn (NafruEmail $n) => $n->contacts->segments->add('c1', 's1'), 'POST', '/contacts/c1/segments/s1'],
            'contacts.segments.remove' => [fn (NafruEmail $n) => $n->contacts->segments->remove('c1', 's1'), 'DELETE', '/contacts/c1/segments/s1'],
            'contacts.topics.list' => [fn (NafruEmail $n) => $n->contacts->topics->list('c1'), 'GET', '/contacts/c1/topics'],
            'contacts.topics.update çıplak dizi' => [fn (NafruEmail $n) => $n->contacts->topics->update('c1', ['topics' => [['id' => 't1', 'subscription' => 'opt_in']]]), 'PATCH', '/contacts/c1/topics', [['id' => 't1', 'subscription' => 'opt_in']]],
            'contactProperties.create' => [fn (NafruEmail $n) => $n->contactProperties->create(['key' => 'plan', 'type' => 'string']), 'POST', '/contact-properties', ['key' => 'plan', 'type' => 'string']],
            'segments.contacts' => [fn (NafruEmail $n) => $n->segments->contacts('s1', ['limit' => 3]), 'GET', '/segments/s1/contacts?limit=3'],
            'segments.create' => [fn (NafruEmail $n) => $n->segments->create(['name' => 'VIP']), 'POST', '/segments', ['name' => 'VIP']],
            'topics.create' => [fn (NafruEmail $n) => $n->topics->create(['name' => 'Haber', 'default_subscription' => 'opt_out']), 'POST', '/topics', ['name' => 'Haber', 'default_subscription' => 'opt_out']],
            'broadcasts.send' => [fn (NafruEmail $n) => $n->broadcasts->send('b1', ['scheduled_at' => 'in 1 hour']), 'POST', '/broadcasts/b1/send', ['scheduled_at' => 'in 1 hour']],
            'broadcasts.cancel' => [fn (NafruEmail $n) => $n->broadcasts->cancel('b1'), 'POST', '/broadcasts/b1/cancel'],
            'templates.publish' => [fn (NafruEmail $n) => $n->templates->publish('welcome'), 'POST', '/templates/welcome/publish'],
            'templates.duplicate' => [fn (NafruEmail $n) => $n->templates->duplicate('t1'), 'POST', '/templates/t1/duplicate'],
            'templates.putTranslation' => [fn (NafruEmail $n) => $n->templates->putTranslation('welcome', 'pt-BR', ['html' => '<p>Olá</p>']), 'PUT', '/templates/welcome/translations/pt-BR', ['html' => '<p>Olá</p>']],
            'templates.removeTranslation' => [fn (NafruEmail $n) => $n->templates->removeTranslation('welcome', 'de'), 'DELETE', '/templates/welcome/translations/de'],
            'templates.update brand' => [fn (NafruEmail $n) => $n->templates->update('welcome', ['brand' => ['mode' => 'inherit']]), 'PATCH', '/templates/welcome', ['brand' => ['mode' => 'inherit']]],
            'brand.get' => [fn (NafruEmail $n) => $n->brand->get(), 'GET', '/brand'],
            'brand.update' => [fn (NafruEmail $n) => $n->brand->update(['accent_color' => '#112233']), 'PUT', '/brand', ['accent_color' => '#112233']],
            'webhooks.create' => [fn (NafruEmail $n) => $n->webhooks->create(['endpoint' => 'https://x.test/h', 'events' => ['email.sent']]), 'POST', '/webhooks', ['endpoint' => 'https://x.test/h', 'events' => ['email.sent']]],
            'apiKeys.create' => [fn (NafruEmail $n) => $n->apiKeys->create(['name' => 'ci']), 'POST', '/api-keys', ['name' => 'ci']],
            'apiKeys.remove' => [fn (NafruEmail $n) => $n->apiKeys->remove('k1'), 'DELETE', '/api-keys/k1'],
            'events.send' => [fn (NafruEmail $n) => $n->events->send(['name' => 'signed_up', 'contact' => ['email' => 'a@x.test']]), 'POST', '/events', ['name' => 'signed_up', 'contact' => ['email' => 'a@x.test']]],
            'events.batch' => [fn (NafruEmail $n) => $n->events->batch([['name' => 'a', 'contact' => ['id' => 'c1']]]), 'POST', '/events/batch', [['name' => 'a', 'contact' => ['id' => 'c1']]]],
            'events.list' => [fn (NafruEmail $n) => $n->events->list(['email' => 'a@x.test']), 'GET', '/events?email=a%40x.test'],
        ];
    }

    #[DataProvider('cases')]
    public function testMapping(\Closure $run, string $method, string $path, mixed $body = null): void
    {
        $t = new MockTransport([Response::json(['ok' => true])]);
        $run(new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false));
        self::assertSame($method, $t->calls[0]['method']);
        self::assertSame('https://api.test' . $path, $t->calls[0]['url']);
        self::assertSame($body, $t->calls[0]['json']);
    }

    public function testBroadcastSendWithoutInputSendsEmptyObject(): void
    {
        $t = new MockTransport([Response::json(['ok' => true])]);
        (new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false))->broadcasts->send('b1');
        self::assertSame('{}', $t->calls[0]['body']);
    }

    public function testBroadcastRecurrenceAndDataSourceRoundTrip(): void
    {
        $detail = [
            'object' => 'broadcast', 'id' => 'b1', 'name' => 'Haftalık', 'status' => 'draft',
            'recurrence' => ['type' => 'weekly', 'days' => [1, 4], 'time' => '09:30'],
            'trigger_state' => 'active', 'next_run_at' => '2026-11-09T06:30:00Z', 'parent_id' => null,
            'data' => ['plan' => 'pro'],
            'data_source' => ['type' => 'url', 'url' => 'https://x.test/d.json', 'header_name' => 'X-Key', 'has_header_value' => true],
        ];
        $unknown = ['object' => 'broadcast', 'id' => 'b2', 'recurrence' => ['type' => 'yearly'], 'data_source' => ['type' => 'gelecekte']];
        $t = new MockTransport([Response::json($detail), Response::json($unknown), Response::json(['object' => 'broadcast', 'id' => 'b3'])]);
        $nafru = new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false);

        $broadcast = $nafru->broadcasts->get('b1');
        self::assertSame([1, 4], $broadcast['recurrence']['days']);
        self::assertSame('active', $broadcast['trigger_state']);
        self::assertNull($broadcast['parent_id']);
        self::assertSame(['plan' => 'pro'], $broadcast['data']);
        self::assertTrue($broadcast['data_source']['has_header_value']);
        self::assertSame('gelecekte', $nafru->broadcasts->get('b2')['data_source']['type']);

        $nafru->broadcasts->create([
            'segment_id' => 's1', 'from' => 'a@x.test', 'subject' => 'S',
            'recurrence' => ['type' => 'interval', 'every_days' => 7, 'time' => '08:00'],
            'data_source' => ['type' => 'webhook', 'regenerate_secret' => true],
            'data' => null,
        ]);
        self::assertSame(
            '{"segment_id":"s1","from":"a@x.test","subject":"S","recurrence":{"type":"interval","every_days":7,"time":"08:00"},"data_source":{"type":"webhook","regenerate_secret":true},"data":null}',
            $t->calls[2]['body'],
        );
    }

    public function testBroadcastUpdateClearsWithNullAndSendCarriesData(): void
    {
        $t = new MockTransport([Response::json(['object' => 'broadcast', 'id' => 'b1'])]);
        $nafru = new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false);
        $nafru->broadcasts->update('b1', ['recurrence' => null, 'data_source' => null]);
        $nafru->broadcasts->send('b1', ['data' => ['kupon' => 'X1']]);
        self::assertSame('{"recurrence":null,"data_source":null}', $t->calls[0]['body']);
        self::assertSame('{"data":{"kupon":"X1"}}', $t->calls[1]['body']);
    }

    public function testPaginateFollowsAfterCursor(): void
    {
        $pages = [
            Response::json(['object' => 'list', 'data' => [['id' => 'a'], ['id' => 'b']], 'has_more' => true]),
            Response::json(['object' => 'list', 'data' => [['id' => 'c']], 'has_more' => false]),
        ];
        $t = new MockTransport($pages);
        $nafru = new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false);
        $ids = array_map(fn ($c) => $c['id'], iterator_to_array(Pagination::paginate($nafru->contacts->list(...), ['limit' => 2]), false));
        self::assertSame(['a', 'b', 'c'], $ids);
        self::assertSame(['https://api.test/contacts?limit=2', 'https://api.test/contacts?limit=2&after=b'], array_column($t->calls, 'url'));
    }

    public function testPaginateThrowsOnError(): void
    {
        $t = new MockTransport([Response::json(['statusCode' => 401, 'name' => 'unauthorized', 'message' => 'anahtar yok'], 401)]);
        $nafru = new NafruEmail('k', 'https://api.test', $t, 0, devOutbox: false);
        $this->expectException(NafruException::class);
        $this->expectExceptionMessage('anahtar yok');
        foreach (Pagination::paginate($nafru->contacts->list(...)) as $_) {
        }
    }
}
