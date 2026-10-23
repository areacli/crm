<?php

namespace App\Demo;

use App\Models\User;

/** Modo de demonstração da instalação pública (config/crm.php). */
final class DemoMode
{
    public static function enabled(): bool
    {
        return (bool) config('crm.demo.enabled');
    }

    public static function domain(): string
    {
        return (string) config('crm.demo.domain');
    }

    /** Os dois usuários públicos: senhas legíveis, que ninguém pode trocar. */
    public static function isPublicUser(?User $user): bool
    {
        return self::enabled() && $user !== null && in_array($user->email, [self::email('gestor'), self::email('operador')], true);
    }

    public static function email(string $who): string
    {
        return $who.'@'.self::domain();
    }
}
