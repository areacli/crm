<?php

namespace Database\Factories;

use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Tenant>
 */
final class TenantFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return ['name' => fake()->unique()->company(), 'active' => true];
    }
}
