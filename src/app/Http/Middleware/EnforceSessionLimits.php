<?php

namespace App\Http\Middleware;

use Closure;
use Filament\Facades\Filament;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/**
 * Limites da sessão (R28 e R25): a sessão vale no máximo 8 horas desde o login (os 30 minutos sem atividade
 * são o tempo de vida da sessão do Laravel), e o usuário desativado ou bloqueado perde a sessão na próxima ação.
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
            $denied = method_exists($user, 'canAccessPanel') && ! $user->canAccessPanel(Filament::getCurrentOrDefaultPanel());

            if ($expired || $denied) {
                Auth::logout();
                $request->session()->invalidate();
                $request->session()->regenerateToken();

                return redirect()->guest(Filament::getLoginUrl());
            }
        }

        return $next($request);
    }
}
