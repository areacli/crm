<?php

namespace App\Filament\Resources\Imports;

use App\Enums\Permission;
use App\Filament\Resources\Imports\Pages\ListImports;
use App\Filament\Resources\Imports\Pages\ViewImport;
use App\Filament\Resources\Imports\Schemas\ImportInfolist;
use App\Filament\Resources\Imports\Tables\ImportsTable;
use App\Models\Import;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/** Importações de carteira: histórico, andamento e resultado da conferência. */
class ImportResource extends Resource
{
    protected static ?string $model = Import::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedDocumentArrowUp;

    protected static ?string $modelLabel = 'importação';

    protected static ?string $pluralModelLabel = 'importações';

    protected static ?string $slug = 'importacoes';

    protected static ?int $navigationSort = 31;

    public static function getEloquentQuery(): Builder
    {
        return Import::query()->visibleTo(Auth::user(), Permission::UploadImports, Permission::ConfirmImports)->where('kind', 'portfolio');
    }

    public static function infolist(Schema $schema): Schema
    {
        return ImportInfolist::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return ImportsTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListImports::route('/'),
            'view' => ViewImport::route('/{record}'),
        ];
    }
}
