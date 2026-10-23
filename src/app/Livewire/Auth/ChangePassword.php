<?php

namespace App\Livewire\Auth;

use App\Demo\DemoMode;
use App\Livewire\Concerns\Toasts;
use App\Models\User;
use App\Rules\StrongPassword;
use App\Support\AccessLog;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Hash;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * Trocar a própria senha (R39) e definir a senha no primeiro acesso, com senha temporária (R38). A nova senha segue a R26 e
 * não pode ser igual à atual nem à temporária; as outras sessões do usuário são encerradas.
 */
#[Layout('layouts.app')]
#[Title('Trocar a senha')]
final class ChangePassword extends Component
{
    use Toasts;

    public string $current_password = '';

    public string $password = '';

    public string $password_confirmation = '';

    public function mount(): void
    {
        // Os usuários públicos da demonstração têm senha legível e ninguém a troca.
        abort_if(DemoMode::isPublicUser(Auth::user()), 403);
    }

    public function save()
    {
        /** @var User $user */
        $user = Auth::user();
        abort_if(DemoMode::isPublicUser($user), 403);

        $this->validate([
            'current_password' => ['required'],
            'password' => ['required', 'same:password_confirmation', new StrongPassword($user->email)],
            'password_confirmation' => ['required'],
        ], ['password.same' => 'A confirmação não confere com a nova senha.'], ['current_password' => 'senha atual', 'password' => 'nova senha', 'password_confirmation' => 'repetição da nova senha']);

        if (! Hash::check($this->current_password, $user->password)) {
            $this->addError('current_password', 'A senha atual não confere.');

            return null;
        }
        if (Hash::check($this->password, $user->password)) {
            $this->addError('password', 'A nova senha não pode ser igual à atual.');

            return null;
        }

        $user->forceFill(['password' => $this->password, 'temporary_password_until' => null])->save();
        // As outras sessões do usuário deixam de valer; a atual segue com o novo hash (R39).
        Auth::logoutOtherDevices($this->password);
        session()->put('password_hash_'.Auth::getDefaultDriver(), $user->getAuthPassword());
        AccessLog::record('password_changed', $user, actor: $user);
        $this->reset('current_password', 'password', 'password_confirmation');
        session()->flash('status', 'Senha alterada');

        return $this->redirectRoute('summary', navigate: false);
    }

    public function render()
    {
        return view('livewire.auth.change-password', ['forced' => Auth::user()->mustChangePassword()]);
    }
}
