<?php

namespace App\Payments;

use App\Enums\PaymentMethod;
use App\Support\BrDate;
use App\Support\Document;
use App\Support\Money;

/** Valida e normaliza uma linha da planilha de pagamentos (R49, R52a). */
final class PaymentRowValidator
{
    public const array REQUIRED = ['canal', 'identificador', 'documento', 'data_pagamento', 'valor', 'meio'];

    public const array OPTIONAL = ['titulo'];

    /**
     * @param  array<string, string>  $row
     * @return array{0: ?array{channel_code: string, identifier: string, document: string, bill_number: string, paid_on: string, amount_cents: int, method: string}, 1: ?string}
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
        if (($row['titulo'] ?? '') === '') {
            // R52a: todo pagamento identifica um título; sem ele a linha é recusada.
            return [null, 'título não informado'];
        }
        if (mb_strlen($row['identificador']) > 200) {
            return [null, 'identificador acima de 200 caracteres'];
        }
        if (mb_strlen($row['canal']) > 100 || mb_strlen($row['titulo']) > 100) {
            return [null, 'canal ou título acima de 100 caracteres'];
        }
        if (($problem = Document::problem($row['documento'])) !== null) {
            return [null, $problem];
        }
        $date = BrDate::parse($row['data_pagamento']);
        if ($date === null) {
            return [null, 'data inválida'];
        }
        if ($date->isFuture()) {
            return [null, 'data de pagamento futura'];
        }
        [$cents, $problem] = Money::parseCents($row['valor']);
        if ($cents === null) {
            return [null, $problem];
        }
        $method = PaymentMethod::fromSheet($row['meio']);
        if ($method === null) {
            return [null, 'meio de pagamento fora da lista'];
        }

        return [[
            'channel_code' => $row['canal'],
            'identifier' => $row['identificador'],
            'document' => Document::normalize($row['documento']),
            'bill_number' => $row['titulo'],
            'paid_on' => $date->toDateString(),
            'amount_cents' => $cents,
            'method' => $method->value,
        ], null];
    }
}
