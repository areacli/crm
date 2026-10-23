<?php

namespace App\Filament\Resources\PaymentImports\Pages;

use App\Filament\Pages\ImportPayments;
use App\Filament\Pages\ImportReversals;
use App\Filament\Resources\PaymentImports\PaymentImportResource;
use Filament\Actions\Action;
use Filament\Resources\Pages\ListRecords;

class ListPaymentImports extends ListRecords
{
    protected static string $resource = PaymentImportResource::class;

    protected static ?string $title = 'Pagamentos e estornos';

    protected function getHeaderActions(): array
    {
        return [
            Action::make('new')->label('Importar pagamentos')->url(ImportPayments::getUrl())->visible(fn () => ImportPayments::canAccess()),
            Action::make('new-reversals')->label('Importar estornos')->color('gray')->url(ImportReversals::getUrl())->visible(fn () => ImportReversals::canAccess()),
        ];
    }
}
