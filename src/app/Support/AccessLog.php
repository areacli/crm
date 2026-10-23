<?php

namespace App\Support;

use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Registro de acessos e de alterações de acesso (R29, R42): quem, quando, em que credor, antes e depois.
 * Senhas nunca entram em `details`.
 */
final class AccessLog
{
    /**
     * @param  array<string, mixed>|null  $details
     */
    public static function record(string $event, ?User $user = null, Tenant|int|null $tenant = null, ?User $actor = null, ?array $details = null, ?string $email = null): void
    {
        $email ??= $user?->email;

        DB::table('access_events')->insert([
            'user_id' => $user?->id,
            'tenant_id' => $tenant instanceof Tenant ? $tenant->id : $tenant,
            'actor_id' => $actor?->id,
            'email' => $email !== null && $email !== '' ? mb_substr($email, 0, 254) : null,
            'event' => $event,
            'ip' => request()?->ip(),
            'details' => $details === null ? null : json_encode($details, JSON_UNESCAPED_UNICODE),
            'occurred_at' => now(),
        ]);
    }
}
