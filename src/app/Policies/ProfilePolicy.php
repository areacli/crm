<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\Profile;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/** Perfis: a permissão 11 vale no credor do perfil (MT-3); perfil de outro credor responde como inexistente. */
final class ProfilePolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageProfiles);
    }

    public function view(User $user, Profile $profile): Response
    {
        return $this->check($user, $profile);
    }

    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ManageProfiles);
    }

    public function update(User $user, Profile $profile): Response
    {
        return $this->check($user, $profile);
    }

    public function delete(User $user, Profile $profile): Response
    {
        return $this->check($user, $profile);
    }

    private function check(User $user, Profile $profile): Response
    {
        return $user->hasPermission(Permission::ManageProfiles, $profile->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }
}
