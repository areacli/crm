<?php

namespace App\Enums;

use App\Support\Contracts\HasLabel;

/** Política do credor para o título retirado, quitado e estornado (R62a). */
enum WithdrawnReversalPolicy: string implements HasLabel
{
    case Reopen = 'reopen';
    case Withdrawn = 'withdrawn';

    public function getLabel(): string
    {
        return match ($this) {
            self::Reopen => 'Volta à cobrança: o título fica ativo com o saldo reaberto',
            self::Withdrawn => 'Volta a retirado: o título fica retirado com o saldo reaberto',
        };
    }
}
