<?php

namespace App\Support;

/** Dados fictícios para a demonstração e as medições: CPF e CNPJ válidos que não pertencem a ninguém conhecido. */
final class FakeData
{
    public static function cpf(int $seed): string
    {
        $digits = array_map('intval', str_split(str_pad((string) (100_000_000 + ($seed * 7919) % 899_999_999), 9, '0', STR_PAD_LEFT)));
        if (count(array_unique($digits)) === 1) {
            $digits[8] = ($digits[8] + 1) % 10;
        }
        foreach ([10, 11] as $length) {
            $sum = 0;
            foreach ($digits as $i => $d) {
                $sum += $d * ($length - $i);
            }
            $digits[] = ($sum * 10) % 11 % 10;
        }

        return implode('', $digits);
    }

    public static function name(int $seed): string
    {
        $first = ['Maria', 'João', 'Ana', 'Pedro', 'Lucas', 'Juliana', 'Carlos', 'Fernanda', 'Rafael', 'Patrícia', 'Bruno', 'Camila'];
        $last = ['Silva', 'Souza', 'Oliveira', 'Santos', 'Pereira', 'Lima', 'Costa', 'Ribeiro', 'Almeida', 'Carvalho', 'Gomes', 'Martins'];

        return $first[$seed % 12].' '.$last[intdiv($seed, 12) % 12].' '.$last[intdiv($seed, 144) % 12].' '.intdiv($seed, 1728);
    }
}
