<?php

namespace App\Enums;

use App\Support\Contracts\HasLabel;

/** Política do credor para pagamento menor que o saldo (R46). */
enum PartialPaymentPolicy: string implements HasLabel
{
    case Partial = 'partial';
    case Credit = 'credit';

    public function getLabel(): string
    {
        return match ($this) {
            self::Partial => 'Baixa parcial: o saldo do título diminui e ele continua em cobrança',
            self::Credit => 'Crédito sem baixar: o título fica como está e o valor vira crédito do contrato',
        };
    }
}
