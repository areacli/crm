<?php

namespace Database\Factories;

use App\Enums\ContactChannel;
use App\Enums\ContactResultType;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Customer;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<ContactAttempt>
 */
final class ContactAttemptFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'customer_id' => Customer::factory(),
            'tenant_id' => fn (array $a) => Customer::query()->findOrFail($a['customer_id'])->tenant_id,
            'result_id' => fn (array $a) => ContactResult::factory()->create(['tenant_id' => Customer::query()->findOrFail($a['customer_id'])->tenant_id])->id,
            'result_type' => ContactResultType::NoContact,
            'channel' => ContactChannel::Phone,
            'contacted_at' => now()->subHour(),
        ];
    }
}
