<?php

use App\Support\AccessLog;
use Illuminate\Auth\Access\AuthorizationException;
use Illuminate\Foundation\Application;
use Illuminate\Foundation\Configuration\Exceptions;
use Illuminate\Foundation\Configuration\Middleware;
use Illuminate\Http\Request;
use Symfony\Component\HttpKernel\Exception\HttpExceptionInterface;

return Application::configure(basePath: dirname(__DIR__))
    ->withRouting(
        web: __DIR__.'/../routes/web.php',
        commands: __DIR__.'/../routes/console.php',
        health: '/up',
    )
    ->withMiddleware(function (Middleware $middleware): void {
        // Atrás do nginx do servidor (TLS): confia nos cabeçalhos X-Forwarded-*. O contêiner web só é alcançável
        // pelo endereço local do servidor, então só esse nginx fala com ele.
        $middleware->trustProxies(at: '*');
    })
    ->withExceptions(function (Exceptions $exceptions): void {
        // R33: acesso recusado por falta de permissão fica registrado (usuário, endereço); a resposta segue o padrão.
        $exceptions->render(function (AuthorizationException $e, Request $request) {
            if ($request->user() !== null) {
                AccessLog::record('permission_denied', $request->user(), details: ['path' => '/'.$request->path(), 'ability' => $e->getMessage()]);
            }

            return null;
        });
        $exceptions->render(function (HttpExceptionInterface $e, Request $request) {
            if ($e->getStatusCode() === 403 && $request->user() !== null) {
                AccessLog::record('permission_denied', $request->user(), details: ['path' => '/'.$request->path()]);
            }

            return null;
        });
        $exceptions->shouldRenderJsonWhen(
            fn (Request $request) => $request->is('api/*') || $request->expectsJson(),
        );
    })->create();
