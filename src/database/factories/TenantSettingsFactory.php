<?php

namespace Database\Factories;

use App\Enums\UpcomingDisplay;
use App\Models\Tenant;
use App\Models\TenantSettings;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<TenantSettings>
 */
final class TenantSettingsFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'aging_brackets' => TenantSettings::DEFAULT_BRACKETS,
            'upcoming_display' => UpcomingDisplay::Separate,
        ];
    }
}
