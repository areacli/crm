<?php

namespace Database\Factories;

use App\Enums\BillStatus;
use App\Models\Bill;
use App\Models\Contract;
use App\Models\Customer;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Bill>
 */
final class BillFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'contract_id' => Contract::factory(),
            'tenant_id' => fn (array $attributes) => Contract::query()->findOrFail($attributes['contract_id'])->tenant_id,
            'customer_id' => fn (array $attributes) => Customer::factory()->create([
                'tenant_id' => Contract::query()->findOrFail($attributes['contract_id'])->tenant_id,
            ])->id,
            'number' => 'NF-'.fake()->unique()->numerify('#####'),
            'due_date' => fake()->dateTimeBetween('-400 days', '+60 days')->format('Y-m-d'),
            'amount_cents' => fake()->numberBetween(5_000, 250_000),
            'description' => null,
            'status' => BillStatus::Active,
        ];
    }

    public function withdrawn(): static
    {
        return $this->state(fn () => ['status' => BillStatus::Withdrawn, 'withdrawn_at' => now()]);
    }
}
