<?php

namespace App\Filament\Resources\Imports\Schemas;

use Filament\Schemas\Components\View;
use Filament\Schemas\Schema;

/** Resultado da importação: andamento, conferência (R10) e linhas recusadas com o motivo. */
class ImportInfolist
{
    public static function configure(Schema $schema): Schema
    {
        return $schema->components([
            View::make('filament.imports.result'),
        ]);
    }
}
