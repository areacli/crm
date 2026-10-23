<?php

namespace Database\Factories;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Models\Import;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Database\Eloquent\Factories\Factory;

/**
 * @extends Factory<Import>
 */
final class ImportFactory extends Factory
{
    #[\Override]
    public function definition(): array
    {
        return [
            'tenant_id' => Tenant::factory(),
            'user_id' => User::factory(),
            'kind' => 'portfolio',
            'mode' => ImportMode::Incremental,
            'status' => ImportStatus::Checked,
            'original_name' => 'carteira.csv',
            'size_bytes' => 0,
        ];
    }
}
