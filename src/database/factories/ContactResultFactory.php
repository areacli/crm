<?php

namespace Database\Factories;

use App\Enums\ContactResultType;
use App\Enums\ReturnRule;
use App\Models\ContactResult;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<ContactResult>
 */
final class ContactResultFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'name' => fake()->unique()->words(3, true),
            'type' => ContactResultType::NoContact,
            'return_rule' => ReturnRule::Allowed,
            'active' => true,
            'position' => 1,
        ];
    }
}
