<?php

namespace App\Access;

use App\Enums\Permission;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\User;

/** Proteções das alterações de acesso, por credor (R41, PD6, PD7, AC7). */
final class AccessGuard
{
    /**
     * R41: depois da alteração, o credor precisa de ao menos um vínculo ativo, de usuário ativo, com "gerenciar
     * usuários" e "gerenciar perfis" ao mesmo tempo. Chamada dentro da transação da alteração, que já a aplicou.
     */
    public static function ensureManagerRemains(int $tenantId): void
    {
        $has = Membership::query()
            ->where('tenant_id', $tenantId)
            ->where('active', true)
            ->whereHas('user', fn ($q) => $q->where('active', true))
            ->whereHas('profile', fn ($q) => $q
                ->whereJsonContains('permissions', Permission::ManageUsers->value)
                ->whereJsonContains('permissions', Permission::ManageProfiles->value))
            ->exists();

        if (! $has) {
            throw new AccessRefused('Ao menos um usuário ativo precisa poder gerenciar usuários e perfis.');
        }
    }

    /** PD7: ninguém muda o próprio perfil nem as permissões do próprio perfil no credor. */
    public static function refuseSelfElevation(User $actor, Membership $target): void
    {
        if ($target->user_id === $actor->id) {
            throw new AccessRefused('Você não pode mudar o seu próprio perfil: outra pessoa com essa permissão faz a alteração.');
        }
    }

    public static function refuseOwnProfileChange(User $actor, Profile $profile): void
    {
        $own = Membership::query()
            ->where('user_id', $actor->id)->where('tenant_id', $profile->tenant_id)->where('profile_id', $profile->id)->exists();

        if ($own) {
            throw new AccessRefused('Você não pode mudar as permissões do seu próprio perfil: outra pessoa com essa permissão faz a alteração.');
        }
    }

    /**
     * PD6 e AC7: 7, 8, 12, 13, 15, 16 e 17 exigem a 1; a 17 exige a 16.
     *
     * @param  list<string>  $permissions
     */
    public static function validatePermissionSet(array $permissions): void
    {
        $needsView = [
            Permission::RecordContactAttempts, Permission::VoidOthersContactAttempts, Permission::EditCustomerRegistry,
            Permission::HandleDataSubjectRights, Permission::CancelPaymentPromises, Permission::NegotiateAgreements,
            Permission::AdministerAgreements,
        ];
        $has = fn (Permission $p) => in_array($p->value, $permissions, true);

        foreach ($needsView as $permission) {
            if ($has($permission) && ! $has(Permission::ViewPortfolio)) {
                throw new AccessRefused('Essas permissões exigem "Consultar a carteira".');
            }
        }
        if ($has(Permission::AdministerAgreements) && ! $has(Permission::NegotiateAgreements)) {
            throw new AccessRefused('"Administrar acordos" exige "Negociar acordos".');
        }
    }
}
