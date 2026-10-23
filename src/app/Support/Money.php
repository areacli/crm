<?php

namespace App\Support;

/** Valores em reais no formato brasileiro, guardados em centavos inteiros (R5, grande regra 2). */
final class Money
{
    /**
     * @return array{0: ?int, 1: ?string} centavos e, quando recusado, o motivo.
     */
    public static function parseCents(string $raw): array
    {
        $value = trim($raw);
        if ($value === '') {
            return [null, 'valor obrigatório'];
        }

        // "1.234,56", "1234,56", "1234" ou "0,5": no máximo duas casas decimais.
        if (! preg_match('/^(\d{1,3}(\.\d{3})+|\d+)(,(\d{1,2}))?$/', $value, $m)) {
            return [null, preg_match('/,\d{3,}$/', $value) ? 'valor com mais de duas casas decimais' : 'valor inválido'];
        }

        $reais = (int) str_replace('.', '', $m[1]);
        $cents = isset($m[4]) ? (int) str_pad($m[4], 2, '0') : 0;
        $total = $reais * 100 + $cents;

        return $total > 0 ? [$total, null] : [null, 'valor deve ser maior que zero'];
    }

    /** 123456 -> "1.234,56". */
    public static function format(int $cents): string
    {
        return number_format($cents / 100, 2, ',', '.');
    }
}
