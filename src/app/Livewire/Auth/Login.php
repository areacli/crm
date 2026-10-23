<?php

namespace App\Livewire\Auth;

use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\RateLimiter;
use Illuminate\Support\Str;
use Illuminate\Validation\ValidationException;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * Entrada (R24 a R29): e-mail e senha. A recusa tem a mesma mensagem para usuário inexistente, senha errada, usuário
 * desativado, bloqueado por tentativas e senha temporária vencida (R27); o bloqueio por usuário é do listener de
 * autenticação, e este componente soma o limite por endereço e e-mail.
 */
#[Layout('layouts.guest')]
#[Title('Entrar')]
final class Login extends Component
{
    public string $email = '';

    public string $password = '';

    public bool $remember = false;

    public function login(): void
    {
        $this->validate(['email' => ['required', 'email'], 'password' => ['required']], [], ['email' => 'e-mail', 'password' => 'senha']);

        $key = Str::lower($this->email).'|'.request()->ip();
        if (RateLimiter::tooManyAttempts($key, 20)) {
            throw ValidationException::withMessages(['email' => 'Muitas tentativas de entrada. Tente de novo em alguns minutos.']);
        }

        $ok = Auth::attemptWhen(
            ['email' => Str::lower(trim($this->email)), 'password' => $this->password],
            fn (User $user) => $user->canEnter(),
            $this->remember,
        );

        if (! $ok) {
            RateLimiter::hit($key, 300);
            $this->password = '';

            throw ValidationException::withMessages(['email' => 'Essas credenciais não correspondem aos nossos registros.']);
        }

        RateLimiter::clear($key);
        session()->regenerate();

        $this->redirectIntended(route('summary'), navigate: false);
    }

    public function render()
    {
        return view('livewire.auth.login');
    }
}
