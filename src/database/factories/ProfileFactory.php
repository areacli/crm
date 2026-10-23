<?php

namespace Database\Factories;

use App\Enums\Permission;
use App\Models\Profile;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Profile>
 */
final class ProfileFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'name' => fake()->unique()->word(),
            'permissions' => [],
        ];
    }

    /** Perfil com todas as permissões da matriz, como o Gestor. */
    public function manager(): static
    {
        return $this->state(fn () => [
            'name' => 'Gestor',
            'permissions' => array_map(fn (Permission $p) => $p->value, Permission::cases()),
        ]);
    }

    /** @param  list<Permission>  $permissions */
    public function allowing(array $permissions): static
    {
        return $this->state(fn () => ['permissions' => array_map(fn (Permission $p) => $p->value, $permissions)]);
    }
}
