<?php

namespace App\Enums;

use App\Support\Contracts\HasColor;
use App\Support\Contracts\HasLabel;

/** Tipo do resultado (R66): classificação fixa por trás da lista livre; não muda depois de criado. */
enum ContactResultType: string implements HasColor, HasLabel
{
    case SpokeWithCustomer = 'spoke_with_customer';
    case SpokeWithThirdParty = 'spoke_with_third_party';
    case NoContact = 'no_contact';

    public function getLabel(): string
    {
        return match ($this) {
            self::SpokeWithCustomer => 'Falou com o cliente',
            self::SpokeWithThirdParty => 'Falou com terceiro',
            self::NoContact => 'Sem contato',
        };
    }

    public function getColor(): string
    {
        return match ($this) {
            self::SpokeWithCustomer => 'success',
            self::SpokeWithThirdParty => 'warning',
            self::NoContact => 'gray',
        };
    }
}
