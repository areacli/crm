<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

/** Política do credor para pagamento de título retirado (R46a). */
enum WithdrawnPaymentPolicy: string implements HasLabel
{
    case Prevails = 'prevails';
    case Credit = 'credit';

    public function getLabel(): string
    {
        return match ($this) {
            self::Prevails => 'O pagamento prevalece: é aplicado ao título retirado',
            self::Credit => 'Vira crédito: o título continua retirado e o valor vira crédito do contrato',
        };
    }
}
