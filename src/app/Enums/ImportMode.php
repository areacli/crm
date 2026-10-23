<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

enum ImportMode: string implements HasLabel
{
    /** Só inclui e atualiza; o que não vem no arquivo não muda (R11). */
    case Incremental = 'incremental';
    /** O arquivo é a carteira inteira: o que não vem passa a retirado (R11). */
    case FullSync = 'full_sync';

    public function getLabel(): string
    {
        return match ($this) {
            self::Incremental => 'Incremental',
            self::FullSync => 'Batimento',
        };
    }
}
