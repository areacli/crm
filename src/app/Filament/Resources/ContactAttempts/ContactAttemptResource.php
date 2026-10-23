<?php

namespace App\Filament\Resources\ContactAttempts;

use App\Enums\ContactChannel;
use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Filament\Resources\ContactAttempts\Pages\ListContactAttempts;
use App\Filament\Resources\Customers\CustomerResource;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Tenant;
use App\Models\User;
use BackedEnum;
use Filament\Forms\Components\DatePicker;
use Filament\Forms\Components\Toggle;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\Filter;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;

/**
 * Lista de acionamentos dos credores em que o usuário consulta a carteira (R78): período (padrão, os últimos 7 dias; no
 * máximo 92 por consulta), operador, canal, resultado e tipo; os anulados ficam fora, salvo se pedidos.
 */
class ContactAttemptResource extends Resource
{
    protected static ?string $model = ContactAttempt::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedPhone;

    protected static ?string $modelLabel = 'acionamento';

    protected static ?string $pluralModelLabel = 'acionamentos';

    protected static ?string $slug = 'acionamentos';

    protected static ?int $navigationSort = 25;

    private const int MAX_PERIOD_DAYS = 92;

    public static function getEloquentQuery(): Builder
    {
        return ContactAttempt::query()->visibleTo(Auth::user(), Permission::ViewPortfolio);
    }

    public static function table(Table $table): Table
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ViewPortfolio);

        return $table
            ->modifyQueryUsing(function (Builder $query, $livewire): Builder {
                // Os anulados ficam fora, salvo se o filtro "incluir anulados" estiver marcado (R78).
                if (! ($livewire->tableFilters['include_voided']['include'] ?? false)) {
                    $query->whereNull('voided_at');
                }

                return $query->with(['customer', 'contract', 'result', 'user', 'tenant']);
            })
            ->defaultSort('contacted_at', 'desc')
            ->paginated([50])
            ->columns([
                TextColumn::make('contacted_at')->label('Contato')->dateTime('d/m/Y H:i')->sortable(),
                TextColumn::make('tenant.name')->label('Credor')->visible(count($ids) > 1),
                TextColumn::make('customer.name')->label('Cliente')
                    ->url(fn (ContactAttempt $r) => CustomerResource::getUrl('view', ['record' => $r->customer_id]))->searchable(),
                TextColumn::make('contract.code')->label('Contrato')->placeholder('—'),
                TextColumn::make('channel')->label('Canal')->badge(),
                TextColumn::make('result.name')->label('Resultado')->description(fn (ContactAttempt $r) => $r->isVoided() ? 'Anulado' : null),
                TextColumn::make('result_type')->label('Tipo')->badge(),
                TextColumn::make('user.name')->label('Operador')->placeholder('—'),
                TextColumn::make('return_at')->label('Retorno')->dateTime('d/m/Y H:i')->placeholder('—'),
            ])
            ->filters([
                // Período: padrão, os últimos 7 dias; no máximo 92 por consulta (R78).
                Filter::make('period')->label('Período')
                    ->schema([
                        DatePicker::make('from')->label('De')->default(now()->subDays(7)->toDateString()),
                        DatePicker::make('until')->label('Até')->default(now()->toDateString()),
                    ])->columns(2)
                    ->query(function (Builder $query, array $data): Builder {
                        $until = Carbon::parse($data['until'] ?? now())->endOfDay();
                        $from = Carbon::parse($data['from'] ?? $until->copy()->subDays(7))->startOfDay();
                        if ($from->diffInDays($until) > self::MAX_PERIOD_DAYS) {
                            $from = $until->copy()->subDays(self::MAX_PERIOD_DAYS)->startOfDay();
                        }

                        return $query->whereBetween('contacted_at', [$from, $until]);
                    })
                    ->indicateUsing(fn (array $data) => ($data['from'] ?? null) ? 'Período: '.Carbon::parse($data['from'])->format('d/m/Y').' a '.Carbon::parse($data['until'] ?? now())->format('d/m/Y') : null),
                SelectFilter::make('user_id')->label('Operador')
                    ->options(fn () => User::query()->whereHas('memberships', fn ($q) => $q->whereIn('tenant_id', $ids ?: [0]))->orderBy('name')->pluck('name', 'id')->all()),
                SelectFilter::make('channel')->label('Canal')->options(ContactChannel::class),
                SelectFilter::make('result_id')->label('Resultado')
                    ->options(fn () => ContactResult::query()->whereIn('tenant_id', $ids ?: [0])->with('tenant')->orderBy('name')->get()
                        ->mapWithKeys(fn (ContactResult $r) => [$r->id => count($ids) > 1 ? $r->name.' ('.$r->tenant->name.')' : $r->name])->all()),
                SelectFilter::make('result_type')->label('Tipo')->options(ContactResultType::class),
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())->visible(count($ids) > 1),
                Filter::make('include_voided')->label('Incluir anulados')->schema([Toggle::make('include')->label('Incluir anulados')])
                    ->query(fn (Builder $query) => $query),
            ])
            ->deferFilters(false)
            ->emptyStateHeading('Nenhum acionamento no período');
    }

    public static function getPages(): array
    {
        return ['index' => ListContactAttempts::route('/')];
    }
}
