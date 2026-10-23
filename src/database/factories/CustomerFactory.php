<?php

namespace Database\Factories;

use App\Models\Customer;
use App\Models\Tenant;
use App\Support\FakeData;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Customer>
 */
final class CustomerFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        $seed = fake()->unique()->numberBetween(1, 50_000_000);

        return [
            'tenant_id' => Tenant::factory(),
            'document' => FakeData::cpf($seed),
            'name' => fake()->name(),
            'phone' => null,
            'email' => null,
        ];
    }
}
