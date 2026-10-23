<?php

namespace App\Models;

use App\Enums\Permission;
use Database\Factories\UserFactory;
use Filament\Models\Contracts\FilamentUser;
use Filament\Panel;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Hidden;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Foundation\Auth\User as Authenticatable;
use Illuminate\Notifications\Notifiable;

#[Fillable(['name', 'email', 'password', 'active'])]
#[Hidden(['password', 'remember_token'])]
class User extends Authenticatable implements FilamentUser
{
    /** @use HasFactory<UserFactory> */
    use HasFactory, Notifiable;

    /** @var array<string, list<int>> */
    private array $tenantIdsCache = [];

    protected function casts(): array
    {
        return [
            'password' => 'hashed',
            'active' => 'boolean',
            'locked_until' => 'datetime',
            'last_login_at' => 'datetime',
        ];
    }

    public function memberships(): HasMany
    {
        return $this->hasMany(Membership::class);
    }

    /**
     * Quem entra: usuário ativo, fora do bloqueio de tentativas (R25, R27) e com vínculo ativo a pelo menos um
     * credor (MT-2). A recusa tem a mesma mensagem para qualquer motivo, e vale a cada requisição, o que
     * derruba as sessões abertas de um usuário desativado (R25).
     */
    public function canAccessPanel(Panel $panel): bool
    {
        return $this->active
            && ! $this->isLocked()
            && $this->memberships()->where('active', true)->exists();
    }

    public function isLocked(): bool
    {
        return $this->locked_until !== null && $this->locked_until->isFuture();
    }

    /**
     * Credores em que o usuário tem a permissão da ação (MT-5): é o escopo de toda consulta.
     *
     * @return list<int>
     */
    public function tenantIdsWith(Permission $permission): array
    {
        return $this->tenantIdsCache[$permission->value] ??= $this->memberships()
            ->where('active', true)
            ->whereHas('profile', fn ($q) => $q->whereJsonContains('permissions', $permission->value))
            ->pluck('tenant_id')
            ->map(fn ($id) => (int) $id)
            ->all();
    }

    /** A permissão é conferida no credor do registro (MT-3). */
    public function hasPermission(Permission $permission, Tenant|int $tenant): bool
    {
        return in_array($tenant instanceof Tenant ? $tenant->id : $tenant, $this->tenantIdsWith($permission), true);
    }

    public function hasAnyPermission(Permission $permission): bool
    {
        return $this->tenantIdsWith($permission) !== [];
    }
}
