<?php

namespace App\Support;

use Illuminate\Support\Carbon;

/** Datas no formato dd/mm/aaaa, com dia e mês sem zero à esquerda aceitos (R6). */
final class BrDate
{
    public static function parse(string $raw): ?Carbon
    {
        if (! preg_match('#^(\d{1,2})/(\d{1,2})/(\d{4})$#', trim($raw), $m)) {
            return null;
        }
        [, $day, $month, $year] = array_map('intval', $m);

        return checkdate($month, $day, $year) ? Carbon::create($year, $month, $day)->startOfDay() : null;
    }
}
