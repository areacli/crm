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
        return $user->hasAnyPermission(Permission::UploadImports) || $user->hasAnyPermission(Permission::ConfirmImports)
            || $user->hasAnyPermission(Permission::UploadPayments) || $user->hasAnyPermission(Permission::ConfirmPayments);
    }

    public function view(User $user, Import $import): Response
    {
        return $this->canSee($user, $import) ? Response::allow() : Response::denyAsNotFound();
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

    /** Abrir a tela de envio de pagamentos ou de estornos: a permissão 5 em algum credor. */
    public function createPayments(User $user): bool
    {
        return $user->hasAnyPermission(Permission::UploadPayments);
    }

    /** Enviar pagamentos ou estornos para um credor específico (permissão 5, R47). */
    public function uploadPayments(User $user, Tenant $tenant): bool
    {
        return $user->hasPermission(Permission::UploadPayments, $tenant);
    }

    /** Confirmar: só uma importação conferida, por quem tem a permissão de confirmar do tipo dela, no credor dela. */
    public function confirm(User $user, Import $import): bool
    {
        return $import->status === ImportStatus::Checked && $user->hasPermission($this->confirmPermission($import), $import->tenant_id);
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

    private function canSee(User $user, Import $import): bool
    {
        return $import->kind === 'portfolio'
            ? $user->hasPermission(Permission::UploadImports, $import->tenant_id) || $user->hasPermission(Permission::ConfirmImports, $import->tenant_id)
            : $user->hasPermission(Permission::UploadPayments, $import->tenant_id) || $user->hasPermission(Permission::ConfirmPayments, $import->tenant_id);
    }

    private function confirmPermission(Import $import): Permission
    {
        return $import->kind === 'portfolio' ? Permission::ConfirmImports : Permission::ConfirmPayments;
    }
}
