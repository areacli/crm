<?php

namespace App\Http\Middleware;

use Closure;
use Illuminate\Http\Request;
use Illuminate\Support\Facades\Auth;
use Symfony\Component\HttpFoundation\Response;

/** R38: com senha temporária, qualquer endereço leva à tela de definir a senha (menos a saída e a própria tela). */
final class RequirePasswordChange
{
    public function handle(Request $request, Closure $next): Response
    {
        $user = Auth::user();

        if ($user !== null && $user->mustChangePassword()
            && ! $request->routeIs('logout', 'password')
            && ! $request->is('livewire*', '*/livewire*')) {
            return redirect()->route('password');
        }

        return $next($request);
    }
}
