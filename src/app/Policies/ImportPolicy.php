<?php

namespace App\Policies;

use App\Enums\ImportStatus;
use App\Enums\Permission;
use App\Models\Import;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Auth\Access\Response;

/**
 * Importações de carteira. Enviar é a permissão 2 e confirmar ou descartar, a 3, sempre no credor da importação (MT-3).
 */
final class ImportPolicy
{
    public function viewAny(User $user): bool
    {
        return $user->hasAnyPermission(Permission::UploadImports) || $user->hasAnyPermission(Permission::ConfirmImports);
    }

    public function view(User $user, Import $import): Response
    {
        return $this->canSee($user, $import->tenant_id) ? Response::allow() : Response::denyAsNotFound();
    }

    /** Abrir a tela de envio: a permissão de enviar em algum credor. */
    public function create(User $user): bool
    {
        return $user->hasAnyPermission(Permission::UploadImports);
    }

    /** Enviar uma planilha para um credor específico (o credor é um campo do formulário, MT-8). */
    public function upload(User $user, Tenant $tenant): bool
    {
        return $user->hasPermission(Permission::UploadImports, $tenant);
    }

    /** Confirmar: só uma importação conferida, por quem tem a permissão 3 no credor dela. */
    public function confirm(User $user, Import $import): bool
    {
        return $import->status === ImportStatus::Checked && $user->hasPermission(Permission::ConfirmImports, $import->tenant_id);
    }

    public function discard(User $user, Import $import): bool
    {
        return $this->confirm($user, $import);
    }

    public function update(User $user, Import $import): bool
    {
        return false;
    }

    public function delete(User $user, Import $import): bool
    {
        return false;
    }

    private function canSee(User $user, int $tenantId): bool
    {
        return $user->hasPermission(Permission::UploadImports, $tenantId) || $user->hasPermission(Permission::ConfirmImports, $tenantId);
    }
}
