<?php

namespace App\Enums;

use App\Support\Contracts\HasLabel;

/** Regra de retorno de um resultado (R66, R73). */
enum ReturnRule: string implements HasLabel
{
    case Required = 'required';
    case Allowed = 'allowed';
    case NotAllowed = 'not_allowed';

    public function getLabel(): string
    {
        return match ($this) {
            self::Required => 'Exige data de retorno',
            self::Allowed => 'Permite data de retorno',
            self::NotAllowed => 'Não permite data de retorno',
        };
    }
}
