<?php

namespace App\Filament\Pages;

use Filament\Support\Icons\Heroicon;

/** Envio da planilha de estornos (R60): mesma tela dos pagamentos, com as colunas dos estornos. */
class ImportReversals extends ImportPayments
{
    protected static string|\BackedEnum|null $navigationIcon = Heroicon::OutlinedArrowUturnLeft;

    protected static ?string $navigationLabel = 'Importar estornos';

    protected static ?string $title = 'Importar estornos';

    protected static ?string $slug = 'importar-estornos';

    protected static ?int $navigationSort = 33;

    protected static string $kind = 'reversals';
}
