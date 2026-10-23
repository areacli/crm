<?php

namespace App\Filament\Resources\Customers\Tables;

use App\Enums\Permission;
use App\Enums\UpcomingDisplay;
use App\Filament\Resources\Customers\CustomerResource;
use App\Models\Customer;
use App\Models\Tenant;
use App\Portfolio\AgingBrackets;
use App\Portfolio\PortfolioQuery;
use App\Support\Document;
use App\Support\Money;
use Filament\Actions\ViewAction;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

class CustomersTable
{
    public static function configure(Table $table): Table
    {
        $user = Auth::user();
        $several = count($user->tenantIdsWith(Permission::ViewPortfolio)) > 1;

        return $table
            // A busca é nossa (sem acento, por nome ou documento, R21): a consulta recebe o termo digitado.
            ->query(fn ($livewire): Builder => (new PortfolioQuery($user))->customers($livewire->tableSearch ?: null, self::bracketFilter($livewire)))
            ->searchable()
            ->searchPlaceholder('Buscar por nome ou documento')
            ->defaultSort(null)
            ->columns([
                TextColumn::make('tenant.name')->label('Credor')->visible($several),
                TextColumn::make('name')->label('Nome')->sortable()->weight('medium'),
                TextColumn::make('document')->label('Documento')
                    ->formatStateUsing(fn (string $state) => Document::mask($state)),
                TextColumn::make('bills_count')->label('Títulos')->numeric()->sortable()->alignEnd(),
                TextColumn::make('overdue_cents')->label('Vencido')->sortable()->alignEnd()
                    ->formatStateUsing(fn ($state) => 'R$ '.Money::format((int) $state)),
                TextColumn::make('upcoming_cents')->label('A vencer')->sortable()->alignEnd()
                    ->formatStateUsing(fn ($state, Customer $record) => self::upcomingText($record, (int) $state)),
                TextColumn::make('max_days_overdue')->label('Maior atraso')->sortable()->alignEnd()
                    ->formatStateUsing(fn ($state) => $state === null ? '—' : $state.' dias'),
                TextColumn::make('bracket')->label('Faixa')->badge()
                    ->state(fn (Customer $record) => (new PortfolioQuery(Auth::user()))->bracketLabel($record->tenant_id, $record->max_days_overdue === null ? null : (int) $record->max_days_overdue)),
            ])
            ->filters([
                // Filtro opcional de credor (MTD2): só para quem vê mais de um; não guarda estado e não é troca de credor.
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $user->tenantIdsWith(Permission::ViewPortfolio))->orderBy('name')->pluck('name', 'id')->all())
                    ->visible($several),
                SelectFilter::make('bracket')->label('Faixa de atraso')
                    ->options(fn () => self::bracketOptions())
                    ->query(fn (Builder $query) => $query), // aplicado na consulta principal (ver bracketFilter)
            ])
            ->recordActions([ViewAction::make()->label('Abrir')])
            ->recordUrl(fn (Customer $record) => CustomerResource::getUrl('view', ['record' => $record]))
            ->emptyStateHeading('Nenhum cliente em cobrança')
            ->emptyStateDescription('Importe a carteira para ver os clientes aqui.');
    }

    private static function bracketFilter($livewire): ?int
    {
        $value = $livewire->tableFilters['bracket']['value'] ?? null;

        return $value === null || $value === '' ? null : (int) $value;
    }

    /** @return array<int|string, string> */
    private static function bracketOptions(): array
    {
        $settings = (new PortfolioQuery(Auth::user()))->settingsByTenant();
        $first = $settings->first();
        $options = ['-1' => 'Sem atraso'];
        if ($first !== null) {
            foreach (AgingBrackets::fromStored($first->aging_brackets)->labels() as $i => $label) {
                $options[(string) $i] = $label;
            }
        }

        return $options;
    }

    /** R20: o "a vencer" aparece conforme a configuração do credor do cliente. */
    private static function upcomingText(Customer $record, int $cents): string
    {
        $mode = (new PortfolioQuery(Auth::user()))->settingsByTenant()[$record->tenant_id]->upcoming_display;

        return match ($mode) {
            UpcomingDisplay::DetailOnly => '—',
            default => 'R$ '.Money::format($cents),
        };
    }
}
