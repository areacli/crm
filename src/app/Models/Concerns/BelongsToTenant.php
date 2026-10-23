<?php

namespace App\Models\Concerns;

use App\Enums\Permission;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Attributes\Scope;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/**
 * Todo registro de domínio pertence a um credor (MT-1). O escopo `visibleTo` limita a consulta aos credores em que o
 * usuário tem a permissão da ação (MT-5): é o único jeito de listar registros, sem seleção de credor na tela.
 */
trait BelongsToTenant
{
    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }

    /**
     * Quando mais de uma permissão é dada, vale o credor em que o usuário tem qualquer uma delas.
     *
     * @param  Builder<static>  $query
     */
    #[Scope]
    protected function visibleTo(Builder $query, User $user, Permission ...$permissions): void
    {
        $ids = array_values(array_unique(array_merge(...array_map(
            fn (Permission $permission) => $user->tenantIdsWith($permission),
            $permissions,
        ))));

        $query->whereIn($query->qualifyColumn('tenant_id'), $ids ?: [0]);
    }
}
