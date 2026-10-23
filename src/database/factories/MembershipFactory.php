<?php

namespace Database\Factories;

use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Membership>
 */
final class MembershipFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'user_id' => User::factory(),
            'tenant_id' => Tenant::factory(),
            'profile_id' => fn (array $attributes) => Profile::factory()->manager()->create(['tenant_id' => $attributes['tenant_id']]),
            'active' => true,
        ];
    }
}
