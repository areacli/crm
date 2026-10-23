<?php

namespace App\Listeners;

use App\Models\User;
use Illuminate\Auth\Events\Failed;
use Illuminate\Auth\Events\Login;
use Illuminate\Auth\Events\Logout;
use Illuminate\Support\Facades\DB;

/**
 * Regras de acesso ligadas aos eventos de autenticação do Laravel (especificação 01, R27 e R29), registradas pela
 * descoberta automática de listeners (métodos `handle*` com o evento na assinatura):
 * bloqueio de 15 minutos após 5 erros seguidos, contagem zerada por login certo, e registro de entradas,
 * saídas, recusas e bloqueios.
 */
final class RecordAuthenticationEvents
{
    public const int MAX_ATTEMPTS = 5;

    public const int LOCK_MINUTES = 15;

    public function handleFailed(Failed $event): void
    {
        $user = $event->user instanceof User ? $event->user : null;
        $email = (string) ($event->credentials['email'] ?? '');

        // Quem já está bloqueado não soma tentativas: a recusa de uma senha certa durante o bloqueio não é erro.
        if ($user !== null && ! $user->isLocked()) {
            $user->increment('failed_attempts');

            if ($user->failed_attempts >= self::MAX_ATTEMPTS) {
                $user->forceFill(['locked_until' => now()->addMinutes(self::LOCK_MINUTES), 'failed_attempts' => 0])->save();
                $this->log('locked', $user, $email);
            }
        }

        $this->log('login_refused', $user, $email);
    }

    public function handleLogin(Login $event): void
    {
        /** @var User $user */
        $user = $event->user;
        $user->forceFill(['failed_attempts' => 0, 'locked_until' => null, 'last_login_at' => now()])->save();
        // Início da sessão, para o limite absoluto de 8 horas (R28).
        session()->put('login_at', now()->timestamp);
        $this->log('login', $user, $user->email);
    }

    public function handleLogout(Logout $event): void
    {
        $this->log('logout', $event->user instanceof User ? $event->user : null, $event->user?->email);
    }

    private function log(string $kind, ?User $user, ?string $email): void
    {
        DB::table('access_events')->insert([
            'user_id' => $user?->id,
            'email' => $email !== null && $email !== '' ? mb_substr($email, 0, 254) : null,
            'event' => $kind,
            'ip' => request()?->ip(),
            'occurred_at' => now(),
        ]);
    }
}
