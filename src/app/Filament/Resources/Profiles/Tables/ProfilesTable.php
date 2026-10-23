<?php

namespace App\Filament\Resources\Profiles\Tables;

use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Enums\Permission;
use App\Models\Profile;
use App\Models\Tenant;
use Filament\Actions\Action;
use Filament\Actions\EditAction;
use Filament\Notifications\Notification;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;

final class ProfilesTable
{
    public static function configure(Table $table): Table
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageProfiles);

        return $table
            ->defaultSort('name')
            ->columns([
                TextColumn::make('tenant.name')->label('Credor')->visible(count($ids) > 1),
                TextColumn::make('name')->label('Perfil')->sortable()->searchable(),
                TextColumn::make('permission_count')->label('Permissões')
                    ->state(fn (Profile $record) => count($record->permissions ?? []))->alignEnd(),
                TextColumn::make('memberships_count')->label('Usuários')->counts('memberships')->alignEnd(),
            ])
            ->filters([
                // Filtro opcional de credor (MTD2): só para quem gerencia perfis em mais de um.
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(count($ids) > 1),
            ])
            ->recordActions([
                EditAction::make()->label('Editar'),
                Action::make('delete')->label('Apagar')->color('danger')->icon('heroicon-o-trash')
                    ->authorize('delete')->requiresConfirmation()
                    ->action(function (Profile $record) {
                        try {
                            app(ProfileManager::class)->delete(Auth::user(), $record);
                            Notification::make()->title('Perfil apagado')->success()->send();
                        } catch (AccessRefused $e) {
                            Notification::make()->title($e->getMessage())->danger()->send();
                        }
                    }),
            ])
            ->emptyStateHeading('Nenhum perfil');
    }
}
