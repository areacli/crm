<?php

namespace App\Filament\Resources\Imports\Tables;

use App\Enums\Permission;
use App\Filament\Resources\Imports\ImportResource;
use App\Models\Import;
use App\Models\Tenant;
use App\Support\Money;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;

class ImportsTable
{
    public static function configure(Table $table): Table
    {
        return $table
            ->defaultSort('id', 'desc')
            // Atualiza sozinha enquanto há importação em andamento: o progresso fica visível (R10).
            ->poll('3s')
            ->columns([
                TextColumn::make('id')->label('Nº')->sortable(),
                TextColumn::make('tenant.name')->label('Credor'),
                TextColumn::make('original_name')->label('Arquivo')->limit(40),
                TextColumn::make('mode')->label('Modo')->badge(),
                TextColumn::make('status')->label('Situação')->badge(),
                TextColumn::make('summary.valid')->label('Válidas')->numeric()->alignEnd()->placeholder('—'),
                TextColumn::make('summary.rejected')->label('Recusadas')->numeric()->alignEnd()->placeholder('—'),
                TextColumn::make('summary.amount_cents')->label('Valor')->alignEnd()->placeholder('—')
                    ->formatStateUsing(fn ($state) => 'R$ '.Money::format((int) $state)),
                TextColumn::make('user.name')->label('Usuário')->placeholder('—'),
                TextColumn::make('created_at')->label('Enviada em')->dateTime('d/m/Y H:i')->sortable(),
            ])
            ->filters([
                // Filtro opcional de credor (MTD2): só para quem vê mais de um credor; não é troca de credor.
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', array_unique([...Auth::user()->tenantIdsWith(Permission::UploadImports), ...Auth::user()->tenantIdsWith(Permission::ConfirmImports)]))->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(fn () => count(array_unique([...Auth::user()->tenantIdsWith(Permission::UploadImports), ...Auth::user()->tenantIdsWith(Permission::ConfirmImports)])) > 1),
            ])
            ->recordUrl(fn (Import $record) => ImportResource::getUrl('view', ['record' => $record]))
            ->emptyStateHeading('Nenhuma importação ainda');
    }
}
