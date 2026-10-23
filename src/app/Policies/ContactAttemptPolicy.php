<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\ContactAttempt;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/** Acionamentos: ver exige a permissão 1; anular, a 7 (o próprio) ou a 8 (de outros), no credor do registro (R75, R76). */
final class ContactAttemptPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ViewPortfolio);
    }

    public function view(User $user, ContactAttempt $attempt): Response
    {
        return $user->hasPermission(Permission::ViewPortfolio, $attempt->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }

    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::RecordContactAttempts);
    }

    public function update(User $user, ContactAttempt $attempt): bool
    {
        return false;
    }

    public function delete(User $user, ContactAttempt $attempt): bool
    {
        return false;
    }

    /** O botão "Anular" aparece só para o acionamento ainda não anulado que o usuário pode anular. */
    public function void(User $user, ContactAttempt $attempt): bool
    {
        if ($attempt->isVoided()) {
            return false;
        }

        return ($attempt->user_id === $user->id && $user->hasPermission(Permission::RecordContactAttempts, $attempt->tenant_id))
            || $user->hasPermission(Permission::VoidOthersContactAttempts, $attempt->tenant_id);
    }
}
