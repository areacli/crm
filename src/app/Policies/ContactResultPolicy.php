<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\ContactResult;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/** Resultados de acionamento: "gerenciar resultados" (9) no credor do resultado (R66, R76). Nada é apagado. */
final class ContactResultPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageContactResults);
    }

    public function view(User $user, ContactResult $result): Response
    {
        return $this->check($user, $result);
    }

    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageContactResults);
    }

    public function update(User $user, ContactResult $result): Response
    {
        return $this->check($user, $result);
    }

    /** R67: resultado não é apagado, só desativado. */
    public function delete(User $user, ContactResult $result): bool
    {
        return false;
    }

    private function check(User $user, ContactResult $result): Response
    {
        return $user->hasPermission(Permission::ManageContactResults, $result->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }
}
