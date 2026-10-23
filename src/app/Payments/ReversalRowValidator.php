<?php

namespace App\Payments;

use App\Support\BrDate;
use App\Support\Money;

/** Valida e normaliza uma linha da planilha de estornos (R60, R61). */
final class ReversalRowValidator
{
    public const array REQUIRED = ['canal', 'identificador_pagamento', 'identificador_estorno', 'data_estorno', 'valor'];

    public const array OPTIONAL = ['motivo'];

    /**
     * @param  array<string, string>  $row
     * @return array{0: ?array{channel_code: string, payment_identifier: string, identifier: string, paid_on: string, amount_cents: int, reason: ?string}, 1: ?string}
     */
    public function validate(array $row): array
    {
        if (($row['__extra'] ?? '') !== '') {
            return [null, 'linha com mais colunas que o cabeçalho'];
        }
        if (($row['__short'] ?? '') !== '') {
            return [null, 'linha incompleta'];
        }
        foreach (self::REQUIRED as $field) {
            if (($row[$field] ?? '') === '') {
                return [null, str_replace('_', ' ', $field).' obrigatório'];
            }
        }
        if (mb_strlen($row['identificador_estorno']) > 200 || mb_strlen($row['identificador_pagamento']) > 200 || mb_strlen($row['canal']) > 100) {
            return [null, 'identificador ou canal acima do limite'];
        }
        if (mb_strlen($row['motivo'] ?? '') > 300) {
            return [null, 'motivo acima de 300 caracteres'];
        }
        $date = BrDate::parse($row['data_estorno']);
        if ($date === null) {
            return [null, 'data inválida'];
        }
        if ($date->isFuture()) {
            return [null, 'data de estorno futura'];
        }
        [$cents, $problem] = Money::parseCents($row['valor']);
        if ($cents === null) {
            return [null, $problem];
        }

        return [[
            'channel_code' => $row['canal'],
            'payment_identifier' => $row['identificador_pagamento'],
            'identifier' => $row['identificador_estorno'],
            'paid_on' => $date->toDateString(),
            'amount_cents' => $cents,
            'reason' => ($row['motivo'] ?? '') !== '' ? $row['motivo'] : null,
        ], null];
    }
}
