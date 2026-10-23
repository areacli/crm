<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\Membership;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/** Usuários do credor (vínculos): a permissão 10 vale no credor do vínculo (MT-3, R36). */
final class MembershipPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageUsers);
    }

    public function view(User $user, Membership $membership): Response
    {
        return $this->check($user, $membership);
    }

    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageUsers);
    }

    public function update(User $user, Membership $membership): Response
    {
        return $this->check($user, $membership);
    }

    public function delete(User $user, Membership $membership): bool
    {
        return false;
    }

    /** R36: quem gerencia não desativa a própria conta. */
    public function deactivate(User $user, Membership $membership): bool
    {
        return $user->hasPermission(Permission::ManageUsers, $membership->tenant_id) && $membership->user_id !== $user->id && $membership->active;
    }

    public function reactivate(User $user, Membership $membership): bool
    {
        return $user->hasPermission(Permission::ManageUsers, $membership->tenant_id) && ! $membership->active;
    }

    /** PD7: ninguém muda o próprio perfil. */
    public function changeProfile(User $user, Membership $membership): bool
    {
        return $user->hasPermission(Permission::ManageUsers, $membership->tenant_id) && $membership->user_id !== $user->id;
    }

    private function check(User $user, Membership $membership): Response
    {
        return $user->hasPermission(Permission::ManageUsers, $membership->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }
}
