<?php

namespace App\Filament\Resources\PaymentChannels;

use App\Enums\ChannelType;
use App\Enums\Permission;
use App\Filament\Resources\PaymentChannels\Pages\CreatePaymentChannel;
use App\Filament\Resources\PaymentChannels\Pages\EditPaymentChannel;
use App\Filament\Resources\PaymentChannels\Pages\ListPaymentChannels;
use App\Models\PaymentChannel;
use App\Models\Tenant;
use BackedEnum;
use Filament\Actions\DeleteAction;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Hidden;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Validation\Rules\Unique;

/** Canais de recebimento do credor: conta, convênio ou estabelecimento de cartão (R45). */
class PaymentChannelResource extends Resource
{
    protected static ?string $model = PaymentChannel::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBuildingLibrary;

    protected static ?string $modelLabel = 'canal de recebimento';

    protected static ?string $pluralModelLabel = 'canais de recebimento';

    protected static ?string $navigationLabel = 'Canais de recebimento';

    protected static ?string $slug = 'canais';

    protected static ?int $navigationSort = 42;

    public static function getEloquentQuery(): Builder
    {
        return PaymentChannel::query()->visibleTo(Auth::user(), Permission::ChangeSettings);
    }

    public static function form(Schema $schema): Schema
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ChangeSettings);

        return $schema->components([
            Select::make('tenant_id')->label('Credor')
                ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                ->required()->disabled(fn (string $operation) => $operation === 'edit')->dehydrated()->live()
                ->visible(count($ids) > 1),
            Hidden::make('tenant_id')->default($ids[0] ?? null)->visible(count($ids) <= 1),
            Select::make('type')->label('Tipo')->options(ChannelType::class)->required(),
            // O código é o que a planilha de pagamentos traz: só muda enquanto o canal não tem pagamento (R45, revisão 7).
            TextInput::make('code')->label('Código')->required()->maxLength(100)
                ->disabled(fn (?PaymentChannel $record) => $record?->payments()->exists() ?? false)->dehydrated()
                ->unique(ignoreRecord: true, modifyRuleUsing: fn (Unique $rule, $get) => $rule->where('tenant_id', $get('tenant_id') ?: Auth::user()->tenantIdsWith(Permission::ChangeSettings)[0] ?? 0)),
            TextInput::make('description')->label('Descrição')->required()->maxLength(200),
            Toggle::make('active')->label('Ativo')->default(true),
        ]);
    }

    public static function table(Table $table): Table
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ChangeSettings);

        return $table
            ->defaultSort('code')
            ->columns([
                TextColumn::make('tenant.name')->label('Credor')->visible(count($ids) > 1),
                TextColumn::make('code')->label('Código')->searchable()->sortable(),
                TextColumn::make('type')->label('Tipo')->badge(),
                TextColumn::make('description')->label('Descrição'),
                IconColumn::make('active')->label('Ativo')->boolean(),
            ])
            ->filters([
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(count($ids) > 1),
            ])
            ->recordActions([
                EditAction::make()->label('Editar'),
                DeleteAction::make()->label('Apagar')->authorize('delete')->requiresConfirmation(),
            ])
            ->emptyStateHeading('Nenhum canal cadastrado');
    }

    public static function getPages(): array
    {
        return [
            'index' => ListPaymentChannels::route('/'),
            'create' => CreatePaymentChannel::route('/novo'),
            'edit' => EditPaymentChannel::route('/{record}/editar'),
        ];
    }

    /** O Filament coloca cada palavra em maiúscula; os textos do CRM seguem a frase em português. */
    #[\Override]
    public static function getTitleCaseModelLabel(): string
    {
        return 'Canal de recebimento';
    }

    #[\Override]
    public static function getTitleCasePluralModelLabel(): string
    {
        return 'Canais de recebimento';
    }
}
