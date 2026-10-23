<?php

namespace App\Policies;

use App\Enums\Permission;
use App\Models\PaymentChannel;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/** Canais de recebimento: "alterar configuração" (4) no credor do canal (R45, R45a). */
final class PaymentChannelPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ChangeSettings);
    }

    public function view(User $user, PaymentChannel $channel): Response
    {
        return $this->check($user, $channel);
    }

    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::ChangeSettings);
    }

    public function update(User $user, PaymentChannel $channel): Response
    {
        return $this->check($user, $channel);
    }

    /** R45 (revisão 7): só o canal sem pagamento pode ser apagado. */
    public function delete(User $user, PaymentChannel $channel): Response
    {
        $check = $this->check($user, $channel);

        return $check->allowed() && ! $channel->payments()->exists() ? Response::allow() : ($check->allowed() ? Response::deny('O canal tem pagamentos: só pode ser desativado.') : $check);
    }

    private function check(User $user, PaymentChannel $channel): Response
    {
        return $user->hasPermission(Permission::ChangeSettings, $channel->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }
}
