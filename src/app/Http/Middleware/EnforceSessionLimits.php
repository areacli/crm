<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Limites da sessão (R28 e R25): a sessão vale no máximo 8 horas desde o login (os 30 minutos sem atividade são o tempo de
 * vida da sessão do Laravel), e o usuário desativado ou bloqueado perde a sessão na próxima ação.
 */
final class EnforceSessionLimits
{
    public const int MAX_SECONDS = 8 * 3600;

    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::user();

        if ($user !== null) {
            $loginAt = (int) $request->session()->get('login_at', 0);
            $expired = $loginAt > 0 && now()->timestamp - $loginAt > self::MAX_SECONDS;

            if ($expired || ! $user->canEnter()) {
                Auth::logout();
                $request->session()->invalidate();
                $request->session()->regenerateToken();

                return $request->header('X-Livewire') ? response()->noContent(401) : redirect()->guest(route('login'));
            }
        }

        return $next($request);
    }
}
