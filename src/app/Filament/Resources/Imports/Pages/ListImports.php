<?php

namespace App\Filament\Resources\Imports\Pages;

use App\Filament\Pages\ImportPortfolio;
use App\Filament\Resources\Imports\ImportResource;
use Filament\Actions\Action;
use Filament\Resources\Pages\ListRecords;

class ListImports extends ListRecords
{
    protected static string $resource = ImportResource::class;

    protected static ?string $title = 'Importações de carteira';

    protected function getHeaderActions(): array
    {
        return [
            Action::make('new')->label('Nova importação')->url(ImportPortfolio::getUrl())
                ->visible(fn () => ImportPortfolio::canAccess()),
        ];
    }
}
