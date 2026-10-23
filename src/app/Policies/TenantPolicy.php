<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\Tenant;
use App\Models\User;

/** Configuração do credor: faixas de atraso e tratamento do a vencer (permissão 4, no credor do registro). */
final class TenantPolicy
{
    /** Abrir a configuração: a permissão de alterar a configuração em algum credor. */
    public function configure(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ChangeSettings);
    }

    public function updateSettings(User $user, Tenant $tenant): bool
    {
        return $user->hasPermission(Permission::ChangeSettings, $tenant);
    }
}
