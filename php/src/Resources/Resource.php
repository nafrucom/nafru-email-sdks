<?php

declare(strict_types=1);

namespace Nafru\Email\Resources;

use Nafru\Email\Http\Requester;
use Nafru\Email\NafruException;

/** @internal */
abstract class Resource
{
    public function __construct(protected readonly Requester $http)
    {
    }

    /** Yol parçası: kimlik ya da e-posta (kişi uçları e-postayı kimlik gibi kabul eder) güvenle kaçırılır. */
    protected static function seg(string $value): string
    {
        // Boş, `.` ve `..` URL normalleştirmesinde başka bir uca gider.
        if ($value === '' || $value === '.' || $value === '..') {
            throw new NafruException(null, 'invalid_argument', "Geçersiz yol parçası: '$value'");
        }
        return rawurlencode($value);
    }
}
