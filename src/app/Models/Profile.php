<?php

namespace App\Models;

use App\Enums\Permission;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\ProfileFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Perfil de um credor: o conjunto de permissões que o vínculo concede (MT-3, MT-21). */
#[Fillable(['tenant_id', 'name', 'permissions'])]
class Profile extends Model
{
    /** @use HasFactory<ProfileFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['permissions' => 'array'];
    }

    public function memberships(): HasMany
    {
        return $this->hasMany(Membership::class);
    }

    public function allows(Permission $permission): bool
    {
        return in_array($permission->value, $this->permissions ?? [], true);
    }

    /** @return list<Permission> */
    public function permissionList(): array
    {
        return array_values(array_filter(array_map(
            fn (string $value) => Permission::tryFrom($value),
            $this->permissions ?? [],
        )));
    }
}
