<?php

namespace App\Access;

use Illuminate\Support\Carbon;

/** Senha temporária (R37): quatro grupos de quatro caracteres sem os que se confundem, válida por 72 horas. */
final class TemporaryPassword
{
    public const int VALID_HOURS = 72;

    private const string ALPHABET = 'abcdefghjkmnpqrstuvwxyzABCDEFGHJKMNPQRSTUVWXYZ23456789';

    public static function generate(): string
    {
        $groups = [];
        for ($i = 0; $i < 4; $i++) {
            $group = '';
            for ($j = 0; $j < 4; $j++) {
                $group .= self::ALPHABET[random_int(0, strlen(self::ALPHABET) - 1)];
            }
            $groups[] = $group;
        }

        return implode('-', $groups);
    }

    public static function expiresAt(): Carbon
    {
        return now()->addHours(self::VALID_HOURS);
    }
}
