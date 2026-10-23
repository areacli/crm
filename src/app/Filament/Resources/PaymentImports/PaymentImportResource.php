<?php

namespace App\Filament\Resources\PaymentImports;

use App\Enums\Permission;
use App\Filament\Resources\PaymentImports\Pages\ListPaymentImports;
use App\Filament\Resources\PaymentImports\Pages\ViewPaymentImport;
use App\Models\Import;
use App\Models\Tenant;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Components\View;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/** Importações de pagamentos e de estornos: histórico, andamento e resultado da conferência (R56, R63). */
class PaymentImportResource extends Resource
{
    protected static ?string $model = Import::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedDocumentCurrencyDollar;

    protected static ?string $modelLabel = 'importação de pagamentos';

    protected static ?string $pluralModelLabel = 'importações de pagamentos';

    protected static ?string $navigationLabel = 'Pagamentos';

    protected static ?string $slug = 'pagamentos';

    protected static ?int $navigationSort = 34;

    public static function getEloquentQuery(): Builder
    {
        return Import::query()->visibleTo(Auth::user(), Permission::UploadPayments, Permission::ConfirmPayments)->whereIn('kind', ['payments', 'reversals']);
    }

    public static function infolist(Schema $schema): Schema
    {
        return $schema->components([View::make('filament.imports.payments-result')]);
    }

    public static function table(Table $table): Table
    {
        $ids = array_unique([...Auth::user()->tenantIdsWith(Permission::UploadPayments), ...Auth::user()->tenantIdsWith(Permission::ConfirmPayments)]);

        return $table
            ->defaultSort('id', 'desc')
            ->poll('3s')
            ->columns([
                TextColumn::make('id')->label('Nº')->sortable(),
                TextColumn::make('kind')->label('Tipo')->formatStateUsing(fn (string $state) => $state === 'reversals' ? 'Estornos' : 'Pagamentos'),
                TextColumn::make('tenant.name')->label('Credor'),
                TextColumn::make('original_name')->label('Arquivo')->limit(40),
                TextColumn::make('status')->label('Situação')->badge(),
                TextColumn::make('summary.valid')->label('Válidas')->numeric()->alignEnd()->placeholder('—'),
                TextColumn::make('summary.rejected')->label('Recusadas')->numeric()->alignEnd()->placeholder('—'),
                TextColumn::make('user.name')->label('Usuário')->placeholder('—'),
                TextColumn::make('created_at')->label('Enviada em')->dateTime('d/m/Y H:i')->sortable(),
            ])
            ->filters([
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(count($ids) > 1),
            ])
            ->recordUrl(fn (Import $record) => static::getUrl('view', ['record' => $record]))
            ->emptyStateHeading('Nenhuma importação de pagamentos ainda');
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPaymentImports::route('/'),
            'view' => ViewPaymentImport::route('/{record}'),
        ];
    }

    /** O Filament coloca cada palavra em maiúscula; os textos do CRM seguem a frase em português. */
    #[\Override]
    public static function getTitleCaseModelLabel(): string
    {
        return 'Importação de pagamentos';
    }

    #[\Override]
    public static function getTitleCasePluralModelLabel(): string
    {
        return 'Importações de pagamentos';
    }
}
