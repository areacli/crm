<?php

namespace App\Access;

use App\Enums\Permission;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Notifications\LinkedToTenant;
use App\Support\AccessLog;
use Illuminate\Support\Facades\DB;

/**
 * Gestão de usuários pela tela (especificação 02, R36 a R42): cada operação confere a permissão 10 no credor do
 * vínculo, aplica a regra de proteção dentro da mesma transação e registra quem, quando, antes e depois.
 */
final class AccessManager
{
    /**
     * R36 e R37: cria o usuário já ligado ao credor, com senha temporária mostrada uma única vez.
     *
     * @return array{0: User, 1: string}
     */
    public function createUser(User $actor, Tenant $tenant, string $email, string $name, Profile $profile): array
    {
        $this->authorize($actor, $tenant);
        $this->ensureProfileBelongs($profile, $tenant);
        $email = mb_strtolower(trim($email));

        return DB::transaction(function () use ($actor, $tenant, $email, $name, $profile) {
            $password = TemporaryPassword::generate();
            $user = User::create(['name' => $name, 'email' => $email, 'password' => $password]);
            $user->forceFill(['temporary_password_until' => TemporaryPassword::expiresAt()])->save();
            Membership::create(['user_id' => $user->id, 'tenant_id' => $tenant->id, 'profile_id' => $profile->id]);
            AccessLog::record('user_created', $user, $tenant, $actor, ['profile' => $profile->name]);

            return [$user, $password];
        });
    }

    /** R36a: liga ao credor um usuário que já existe; vale na hora e o usuário recebe um aviso. */
    public function linkExisting(User $actor, Tenant $tenant, User $user, Profile $profile): Membership
    {
        $this->authorize($actor, $tenant);
        $this->ensureProfileBelongs($profile, $tenant);

        $membership = DB::transaction(function () use ($actor, $tenant, $user, $profile) {
            $existing = Membership::where('user_id', $user->id)->where('tenant_id', $tenant->id)->first();
            if ($existing !== null && $existing->active) {
                throw new AccessRefused('Esse usuário já está ligado a este credor.');
            }
            $membership = $existing ?? new Membership(['user_id' => $user->id, 'tenant_id' => $tenant->id]);
            $membership->fill(['profile_id' => $profile->id, 'active' => true])->save();
            AccessLog::record('membership_linked', $user, $tenant, $actor, ['profile' => $profile->name]);

            return $membership;
        });

        $user->notify(new LinkedToTenant($tenant->name, $actor->name, $profile->name));

        return $membership;
    }

    /** R32, R41, PD7: muda o perfil do vínculo. */
    public function changeProfile(User $actor, Membership $membership, Profile $profile): void
    {
        $this->authorize($actor, $membership->tenant_id);
        $this->ensureProfileBelongs($profile, $membership->tenant);
        AccessGuard::refuseSelfElevation($actor, $membership);

        DB::transaction(function () use ($actor, $membership, $profile) {
            $before = $membership->profile->name;
            $membership->update(['profile_id' => $profile->id]);
            AccessGuard::ensureManagerRemains($membership->tenant_id);
            AccessLog::record('profile_changed', $membership->user, $membership->tenant_id, $actor, ['before' => $before, 'after' => $profile->name]);
        });
    }

    /** R40: desativar ou reativar o vínculo; o usuário segue nos outros credores. */
    public function setActive(User $actor, Membership $membership, bool $active): void
    {
        $this->authorize($actor, $membership->tenant_id);
        if (! $active && $membership->user_id === $actor->id) {
            throw new AccessRefused('Você não pode desativar a própria conta.');
        }

        DB::transaction(function () use ($actor, $membership, $active) {
            $membership->update(['active' => $active]);
            if (! $active) {
                AccessGuard::ensureManagerRemains($membership->tenant_id);
            }
            AccessLog::record($active ? 'membership_reactivated' : 'membership_deactivated', $membership->user, $membership->tenant_id, $actor);
        });
    }

    /** R36 (revisão 3): altera o nome; R36a: não de quem atua também em outro credor. */
    public function rename(User $actor, Membership $membership, string $name): void
    {
        $this->authorizePersonal($actor, $membership);
        $before = $membership->user->name;

        DB::transaction(function () use ($actor, $membership, $name, $before) {
            $membership->user->update(['name' => $name]);
            AccessLog::record('user_renamed', $membership->user, $membership->tenant_id, $actor, ['before' => $before, 'after' => $name]);
        });
    }

    /** R37: redefine a senha, com nova temporária mostrada uma única vez; a anterior deixa de valer. */
    public function resetPassword(User $actor, Membership $membership): string
    {
        $this->authorizePersonal($actor, $membership);
        $password = TemporaryPassword::generate();

        DB::transaction(function () use ($actor, $membership, $password) {
            $membership->user->forceFill([
                'password' => $password,
                'temporary_password_until' => TemporaryPassword::expiresAt(),
                'failed_attempts' => 0,
                'locked_until' => null,
            ])->save();
            AccessLog::record('password_reset', $membership->user, $membership->tenant_id, $actor);
        });

        return $password;
    }

    /** Nome e senha são da pessoa (R36a): só se o usuário não tem vínculo em outro credor. */
    public function isPersonalEditable(Membership $membership): bool
    {
        return ! Membership::where('user_id', $membership->user_id)->where('tenant_id', '!=', $membership->tenant_id)->exists();
    }

    private function authorizePersonal(User $actor, Membership $membership): void
    {
        $this->authorize($actor, $membership->tenant_id);
        if (! $this->isPersonalEditable($membership)) {
            throw new AccessRefused('Nome e senha de quem atua também em outro credor só o próprio usuário e o administrador alteram.');
        }
    }

    private function authorize(User $actor, Tenant|int $tenant): void
    {
        if (! $actor->hasPermission(Permission::ManageUsers, $tenant)) {
            AccessLog::record('permission_denied', $actor, $tenant, $actor, ['permission' => Permission::ManageUsers->value]);

            throw new AccessRefused('Você não tem permissão para esta ação.');
        }
    }

    private function ensureProfileBelongs(Profile $profile, Tenant $tenant): void
    {
        if ($profile->tenant_id !== $tenant->id) {
            throw new AccessRefused('O perfil não é deste credor.');
        }
    }
}
