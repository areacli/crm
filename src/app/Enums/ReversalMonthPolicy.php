<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

/** Mês em que o estorno desconta do valor recuperado (R64). */
enum ReversalMonthPolicy: string implements HasLabel
{
    case Reversal = 'reversal';
    case Payment = 'payment';

    public function getLabel(): string
    {
        return match ($this) {
            self::Reversal => 'No mês do estorno (meses anteriores não mudam)',
            self::Payment => 'No mês do pagamento estornado',
        };
    }
}
