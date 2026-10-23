<?php

namespace App\Enums;

use Filament\Support\Contracts\HasLabel;

/** Canal do contato: lista fixa (R65). */
enum ContactChannel: string implements HasLabel
{
    case Phone = 'phone';
    case WhatsApp = 'whatsapp';
    case Sms = 'sms';
    case Email = 'email';
    case Letter = 'letter';
    case InPerson = 'in_person';
    case Other = 'other';

    public function getLabel(): string
    {
        return match ($this) {
            self::Phone => 'Telefone',
            self::WhatsApp => 'WhatsApp',
            self::Sms => 'SMS',
            self::Email => 'E-mail',
            self::Letter => 'Carta',
            self::InPerson => 'Presencial',
            self::Other => 'Outro',
        };
    }
}
