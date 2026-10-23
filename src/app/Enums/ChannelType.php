<?php

namespace App\Enums;

use App\Support\Contracts\HasLabel;

/** Tipo do canal de recebimento (R45); só leitura, não entra em cálculo. */
enum ChannelType: string implements HasLabel
{
    case Account = 'account';
    case Agreement = 'agreement';
    case Card = 'card';

    public function getLabel(): string
    {
        return match ($this) {
            self::Account => 'Conta bancária',
            self::Agreement => 'Convênio de cobrança',
            self::Card => 'Estabelecimento de cartão',
        };
    }
}
