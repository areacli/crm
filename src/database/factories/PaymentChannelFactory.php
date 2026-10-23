<?php

namespace Database\Factories;

use App\Enums\ChannelType;
use App\Models\PaymentChannel;
use App\Models\Tenant;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<PaymentChannel>
 */
final class PaymentChannelFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'type' => ChannelType::Account,
            'code' => fake()->unique()->numerify('341-####-#####'),
            'description' => 'Conta principal',
            'active' => true,
        ];
    }
}
