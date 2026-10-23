<?php

namespace Database\Factories;

use App\Enums\PaymentMethod;
use App\Models\Payment;
use App\Models\PaymentChannel;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Payment>
 */
final class PaymentFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => fn (array $a) => PaymentChannel::query()->findOrFail($a['channel_id'])->tenant_id,
            'channel_id' => PaymentChannel::factory(),
            'identifier' => fake()->unique()->bothify('E##########??'),
            'document' => '52998224725',
            'bill_number' => 'NF-1',
            'paid_on' => now()->subDay()->toDateString(),
            'amount_cents' => 10_000,
            'method' => PaymentMethod::Pix,
            'status' => Payment::APPLIED,
        ];
    }
}
