<?php

namespace Database\Factories;

use App\Models\Contract;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Contract>
 */
final class ContractFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'code' => 'CT-'.fake()->unique()->numerify('#######'),
            'created_by_omission' => false,
        ];
    }

    /** Contrato criado pela importação quando a planilha não o traz (MT-14). */
    public function byOmission(): static
    {
        return $this->state(fn () => ['code' => null, 'created_by_omission' => true]);
    }
}
