<?php

namespace App\Access;

use App\Enums\Permission;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Support\AccessLog;
use Illuminate\Support\Facades\DB;

/** Perfis por credor (R30 a R35): cria, altera e apaga com as proteções de R35, R41, PD6, PD7 e AC7. */
final class ProfileManager
{
    /** @param  list<string>  $permissions */
    public function create(User $actor, Tenant $tenant, string $name, array $permissions): Profile
    {
        $this->authorize($actor, $tenant->id);
        AccessGuard::validatePermissionSet($permissions);

        return DB::transaction(function () use ($actor, $tenant, $name, $permissions) {
            $profile = Profile::create(['tenant_id' => $tenant->id, 'name' => $name, 'permissions' => $this->normalize($permissions)]);
            AccessLog::record('profile_created', null, $tenant, $actor, ['profile' => $name, 'after' => $profile->permissions]);

            return $profile;
        });
    }

    /** @param  list<string>  $permissions */
    public function update(User $actor, Profile $profile, string $name, array $permissions): void
    {
        $this->authorize($actor, $profile->tenant_id);
        AccessGuard::validatePermissionSet($permissions);
        $permissions = $this->normalize($permissions);

        if ($permissions !== $this->normalize($profile->permissions ?? [])) {
            AccessGuard::refuseOwnProfileChange($actor, $profile);
        }

        DB::transaction(function () use ($actor, $profile, $name, $permissions) {
            $before = ['name' => $profile->name, 'permissions' => $profile->permissions];
            $profile->update(['name' => $name, 'permissions' => $permissions]);
            AccessGuard::ensureManagerRemains($profile->tenant_id);
            AccessLog::record('profile_updated', null, $profile->tenant_id, $actor, [
                'profile' => $name, 'before' => $before, 'after' => ['name' => $name, 'permissions' => $permissions],
            ]);
        });
    }

    /** R35: perfil com usuários não se apaga. */
    public function delete(User $actor, Profile $profile): void
    {
        $this->authorize($actor, $profile->tenant_id);
        $users = Membership::where('profile_id', $profile->id)->count();
        if ($users > 0) {
            throw new AccessRefused("Perfil em uso por {$users} ".($users === 1 ? 'usuário.' : 'usuários.'));
        }

        DB::transaction(function () use ($actor, $profile) {
            $profile->delete();
            AccessLog::record('profile_deleted', null, $profile->tenant_id, $actor, ['profile' => $profile->name]);
        });
    }

    private function authorize(User $actor, int $tenantId): void
    {
        if (! $actor->hasPermission(Permission::ManageProfiles, $tenantId)) {
            AccessLog::record('permission_denied', $actor, $tenantId, $actor, ['permission' => Permission::ManageProfiles->value]);

            throw new AccessRefused('Você não tem permissão para esta ação.');
        }
    }

    /**
     * Só permissões conhecidas, sem repetição, na ordem da matriz.
     *
     * @param  list<string>  $permissions
     * @return list<string>
     */
    private function normalize(array $permissions): array
    {
        return array_values(array_map(
            fn (Permission $p) => $p->value,
            array_filter(Permission::cases(), fn (Permission $p) => in_array($p->value, $permissions, true)),
        ));
    }
}
