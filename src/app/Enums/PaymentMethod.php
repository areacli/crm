<?php

namespace App\Enums;

use App\Support\Text;
use Filament\Support\Contracts\HasLabel;

/** Meio de pagamento da planilha (R49): a lista é fechada. */
enum PaymentMethod: string implements HasLabel
{
    case Pix = 'pix';
    case Boleto = 'boleto';
    case CreditCard = 'credit_card';
    case DebitCard = 'debit_card';
    case Transfer = 'transfer';
    case Cash = 'cash';
    case Other = 'other';

    public function getLabel(): string
    {
        return match ($this) {
            self::Pix => 'Pix',
            self::Boleto => 'Boleto',
            self::CreditCard => 'Cartão de crédito',
            self::DebitCard => 'Cartão de débito',
            self::Transfer => 'Transferência',
            self::Cash => 'Dinheiro',
            self::Other => 'Outro',
        };
    }

    /** Lê o valor da planilha, sem diferenciar maiúsculas nem acentos; null quando fora da lista. */
    public static function fromSheet(string $raw): ?self
    {
        return match (str_replace([' ', '-', '_'], '', Text::fold($raw))) {
            'pix' => self::Pix,
            'boleto' => self::Boleto,
            'cartaodecredito', 'cartaocredito' => self::CreditCard,
            'cartaododebito', 'cartaodebito', 'cartaodedebito' => self::DebitCard,
            'transferencia' => self::Transfer,
            'dinheiro' => self::Cash,
            'outro' => self::Other,
            default => null,
        };
    }
}
