<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\Customer;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/**
 * Clientes: só leitura neste incremento (cadastro, edição e exclusão manual estão fora do escopo da especificação 01).
 * A permissão de consultar é conferida no credor do cliente (MT-3).
 */
final class CustomerPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ViewPortfolio);
    }

    /** Cliente de credor sem acesso responde como "não encontrado", para não revelar que existe (MT-5). */
    public function view(User $user, Customer $customer): Response
    {
        return $user->hasPermission(Permission::ViewPortfolio, $customer->tenant_id)
            ? Response::allow()
            : Response::denyAsNotFound();
    }

    public function create(User $user): bool
    {
        return false;
    }

    public function update(User $user, Customer $customer): bool
    {
        return false;
    }

    public function delete(User $user, Customer $customer): bool
    {
        return false;
    }

    /** Transferir crédito entre contratos: permissão 17 e a 1 (PD6), no credor do cliente (11, R239a; 03, R55a). */
    public function transferCredit(User $user, Customer $customer): bool
    {
        return $user->hasPermission(Permission::AdministerAgreements, $customer->tenant_id)
            && $user->hasPermission(Permission::ViewPortfolio, $customer->tenant_id);
    }
}
