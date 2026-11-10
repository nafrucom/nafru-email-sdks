<?php

declare(strict_types=1);

namespace Nafru\Email;

final class Pagination
{
    /**
     * Bir liste çağrısını tüm sayfalar boyunca gezer (`after` imleci, en yeni önce sırasında ileri). Hata gelirse `NafruException`
     * yükselir: sayfalama döngüsünde sessizce kesmek eksik veri okutur.
     *
     *     foreach (Pagination::paginate($nafru->contacts->list(...), ['limit' => 100]) as $contact) { … }
     *
     * @template T of array{id: string}
     * @param callable(array<string, mixed>): array{data: list<T>, has_more: bool} $list
     * @param array<string, mixed> $query `after`/`before` dışındaki sorgu
     * @return \Generator<int, T>
     */
    public static function paginate(callable $list, array $query = []): \Generator
    {
        unset($query['after'], $query['before']);
        $after = null;
        while (true) {
            $page = $list($after === null ? $query : $query + ['after' => $after]);
            foreach ($page['data'] as $item) {
                yield $item;
            }
            $lastItem = $page['data'] === [] ? null : $page['data'][array_key_last($page['data'])];
            if (empty($page['has_more']) || $lastItem === null) {
                return;
            }
            $after = $lastItem['id'];
        }
    }
}
