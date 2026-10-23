<?php

namespace App\Filament\Resources\Customers\Schemas;

use App\Livewire\CustomerContactAttempts;
use App\Models\Customer;
use Filament\Infolists\Components\TextEntry;
use Filament\Schemas\Components\Livewire;
use Filament\Schemas\Components\Section;
use Filament\Schemas\Components\View;
use Filament\Schemas\Schema;

/** Ficha do cliente (R22): dados de contato e títulos agrupados por contrato, com os retirados à parte. */
class CustomerInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema->components([
            Section::make('Dados')
                ->columns(2)
                ->schema([
                    TextEntry::make('name')->label('Nome'),
                    TextEntry::make('document')->label('Documento')->formatStateUsing(fn (string $state) => self::formatDocument($state)),
                    TextEntry::make('phone')->label('Telefone')->placeholder('—'),
                    TextEntry::make('email')->label('E-mail')->placeholder('—'),
                    TextEntry::make('tenant.name')->label('Credor'),
                ]),
            View::make('filament.customers.bills'),
            Livewire::make(CustomerContactAttempts::class, fn (Customer $record) => ['customerId' => $record->id])->key('contact-attempts')->columnSpanFull(),
        ]);
    }

    private static function formatDocument(string $document): string
    {
        if (strlen($document) === 11) {
            return substr($document, 0, 3).'.'.substr($document, 3, 3).'.'.substr($document, 6, 3).'-'.substr($document, 9, 2);
        }

        return substr($document, 0, 2).'.'.substr($document, 2, 3).'.'.substr($document, 5, 3).'/'.substr($document, 8, 4).'-'.substr($document, 12, 2);
    }
}
