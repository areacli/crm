<?php

namespace App\Filament\Resources\Memberships\Tables;

use App\Access\AccessManager;
use App\Access\AccessRefused;
use App\Enums\Permission;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use Filament\Actions\Action;
use Filament\Actions\ActionGroup;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;

final class MembershipsTable
{
    public static function configure(Table $table): Table
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageUsers);
        $manager = fn () => app(AccessManager::class);

        return $table
            ->columns([
                TextColumn::make('user.name')->label('Nome')->searchable(),
                TextColumn::make('user.email')->label('E-mail')->searchable(),
                TextColumn::make('tenant.name')->label('Credor')->visible(count($ids) > 1),
                TextColumn::make('profile.name')->label('Perfil'),
                IconColumn::make('active')->label('Ativo')->boolean(),
                TextColumn::make('user.last_login_at')->label('Último acesso')->dateTime('d/m/Y H:i')->placeholder('—'),
            ])
            ->filters([
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(count($ids) > 1),
            ])
            ->recordActions([ActionGroup::make([
                Action::make('profile')->label('Mudar o perfil')->icon('heroicon-o-identification')
                    ->authorize('changeProfile')
                    ->schema([Select::make('profile_id')->label('Perfil')->required()
                        ->options(fn (Membership $record) => Profile::where('tenant_id', $record->tenant_id)->orderBy('name')->pluck('name', 'id')->all())])
                    ->fillForm(fn (Membership $record) => ['profile_id' => $record->profile_id])
                    ->action(fn (Membership $record, array $data) => self::run(fn () => $manager()->changeProfile(Auth::user(), $record, Profile::findOrFail($data['profile_id'])), 'Perfil alterado')),
                Action::make('rename')->label('Alterar o nome')->icon('heroicon-o-pencil')
                    ->authorize('update')
                    ->visible(fn (Membership $record) => $manager()->isPersonalEditable($record))
                    ->schema([TextInput::make('name')->label('Nome')->required()->maxLength(150)])
                    ->fillForm(fn (Membership $record) => ['name' => $record->user->name])
                    ->action(fn (Membership $record, array $data) => self::run(fn () => $manager()->rename(Auth::user(), $record, $data['name']), 'Nome alterado')),
                Action::make('reset')->label('Redefinir a senha')->icon('heroicon-o-key')
                    ->authorize('update')
                    ->visible(fn (Membership $record) => $manager()->isPersonalEditable($record))
                    ->requiresConfirmation()
                    ->modalDescription('Gera uma senha temporária, válida por 72 horas, mostrada uma única vez. A senha anterior deixa de valer.')
                    ->action(function (Membership $record) use ($manager) {
                        try {
                            $password = $manager()->resetPassword(Auth::user(), $record);
                            Notification::make()->title("Senha de {$record->user->email} redefinida")
                                ->body("Senha temporária (não será mostrada de novo): {$password}")->success()->persistent()->send();
                        } catch (AccessRefused $e) {
                            Notification::make()->title($e->getMessage())->danger()->send();
                        }
                    }),
                Action::make('deactivate')->label('Desativar')->icon('heroicon-o-no-symbol')->color('danger')
                    ->authorize('deactivate')->requiresConfirmation()
                    ->modalDescription('Desativa o acesso da pessoa a este credor. Ela segue nos outros credores, se houver.')
                    ->action(fn (Membership $record) => self::run(fn () => $manager()->setActive(Auth::user(), $record, false), 'Acesso desativado')),
                Action::make('reactivate')->label('Reativar')->icon('heroicon-o-check-circle')
                    ->authorize('reactivate')
                    ->action(fn (Membership $record) => self::run(fn () => $manager()->setActive(Auth::user(), $record, true), 'Acesso reativado')),
                Action::make('history')->label('Histórico')->icon('heroicon-o-clock')
                    ->authorize('view')
                    ->modalHeading(fn (Membership $record) => "Histórico de {$record->user->email} em {$record->tenant->name}")
                    ->modalSubmitAction(false)->modalCancelActionLabel('Fechar')->slideOver()
                    ->modalContent(fn (Membership $record) => view('filament.users.history', [
                        'events' => DB::table('access_events')
                            ->where('user_id', $record->user_id)
                            ->where(fn ($q) => $q->where('tenant_id', $record->tenant_id)->orWhereNull('tenant_id'))
                            ->orderByDesc('occurred_at')->orderByDesc('id')->limit(100)->get(),
                    ])),
            ])->label('Ações')])
            ->emptyStateHeading('Nenhum usuário');
    }

    private static function run(callable $change, string $done): void
    {
        try {
            $change();
            Notification::make()->title($done)->success()->send();
        } catch (AccessRefused $e) {
            Notification::make()->title($e->getMessage())->danger()->send();
        }
    }
}
