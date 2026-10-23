<?php

namespace App\Tenancy;

use App\Enums\Permission;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\TenantSettings;
use Illuminate\Support\Facades\DB;

/**
 * Cria um credor com a configuração inicial e os perfis padrão, copiados de um modelo (MT-21): alterar o perfil
 * de um credor não altera o de outro.
 */
final class TenantProvisioner
{
    /** Perfis padrão e suas permissões (matriz de permissões). */
    public const array PROFILES = [
        'Gestor' => 'all',
        'Operador' => [
            Permission::ViewPortfolio,
            Permission::RecordContactAttempts,
            Permission::EditCustomerRegistry,
            Permission::NegotiateAgreements,
        ],
    ];

    public function create(string $name): Tenant
    {
        return DB::transaction(function () use ($name) {
            $tenant = Tenant::create(['name' => $name]);
            TenantSettings::create(['tenant_id' => $tenant->id, 'aging_brackets' => TenantSettings::DEFAULT_BRACKETS]);

            foreach (self::PROFILES as $profileName => $permissions) {
                $list = $permissions === 'all' ? Permission::cases() : $permissions;
                Profile::create([
                    'tenant_id' => $tenant->id,
                    'name' => $profileName,
                    'permissions' => array_map(fn (Permission $p) => $p->value, $list),
                ]);
            }

            return $tenant;
        });
    }
}
