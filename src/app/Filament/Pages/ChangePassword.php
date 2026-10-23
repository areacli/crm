<?php

namespace App\Filament\Pages;

use App\Models\User;
use App\Rules\StrongPassword;
use App\Support\AccessLog;
use BackedEnum;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Illuminate\Validation\ValidationException;

/**
 * Trocar a própria senha (R39) e definir a senha no primeiro acesso, com senha temporária (R38). A nova senha
 * segue a R26 e não pode ser igual à atual nem à temporária; as outras sessões do usuário são encerradas.
 */
final class ChangePassword extends Page
{
    protected static ?string $slug = 'senha';

    protected static ?string $title = 'Trocar a senha';

    protected static bool $shouldRegisterNavigation = false;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedKey;

    protected string $view = 'filament.pages.change-password';

    /** @var array<string, mixed> */
    public array $data = [];

    public function mount(): void
    {
        $this->form->fill();
    }

    public function form(Schema $schema): Schema
    {
        return $schema->statePath('data')->components([
            TextInput::make('current_password')->label('Senha atual')->password()->revealable()->required(),
            TextInput::make('password')->label('Nova senha')->password()->revealable()->required()
                ->helperText('Mínimo de 12 caracteres, sem ser comum, só números ou parecida com o seu e-mail.')
                ->rule(fn () => new StrongPassword(Auth::user()->email)),
            TextInput::make('password_confirmation')->label('Repita a nova senha')->password()->revealable()->required()
                ->same('password'),
        ]);
    }

    public function save(): void
    {
        $data = $this->form->getState();
        /** @var User $user */
        $user = Auth::user();

        if (! Hash::check($data['current_password'], $user->password)) {
            throw ValidationException::withMessages(['data.current_password' => 'A senha atual não confere.']);
        }
        if (Hash::check($data['password'], $user->password)) {
            throw ValidationException::withMessages(['data.password' => 'A nova senha não pode ser igual à atual.']);
        }

        $user->forceFill(['password' => $data['password'], 'temporary_password_until' => null])->save();
        // As outras sessões do usuário deixam de valer; a atual segue com o novo hash (R39).
        Auth::logoutOtherDevices($data['password']);
        session()->put('password_hash_'.Auth::getDefaultDriver(), $user->getAuthPassword());
        AccessLog::record('password_changed', $user, actor: $user);

        Notification::make()->title('Senha alterada')->success()->send();
        $this->redirect(Summary::getUrl());
    }
}
