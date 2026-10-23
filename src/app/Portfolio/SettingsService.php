<?php

namespace App\Portfolio;

use App\Enums\UpcomingDisplay;
use App\Models\Change;
use App\Models\Tenant;
use App\Models\User;

/** Configuração do credor: faixas de atraso (R18) e tratamento do a vencer (R20), com histórico. */
final class SettingsService
{
    /**
     * @param  list<array{from: mixed, to: mixed}>  $input
     *
     * @throws InvalidBrackets
     */
    public function updateBrackets(Tenant $tenant, array $input, User $user): void
    {
        $new = AgingBrackets::from($input);
        $settings = $tenant->settings;
        $before = json_encode($settings->aging_brackets);

        $settings->update(['aging_brackets' => $new->brackets]);
        $this->log($tenant, $user, 'brackets_changed', 'aging_brackets', $before, json_encode($new->brackets));
    }

    public function updateUpcomingDisplay(Tenant $tenant, UpcomingDisplay $display, User $user): void
    {
        $settings = $tenant->settings;
        $before = $settings->upcoming_display->value;
        $settings->update(['upcoming_display' => $display]);

        if ($before !== $display->value) {
            $this->log($tenant, $user, 'upcoming_display_changed', 'upcoming_display', $before, $display->value);
        }
    }

    private function log(Tenant $tenant, User $user, string $event, string $field, ?string $before, ?string $after): void
    {
        Change::create([
            'tenant_id' => $tenant->id,
            'user_id' => $user->id,
            'subject_type' => 'settings',
            'subject_id' => $tenant->id,
            'event' => $event,
            'field' => $field,
            'before' => $before,
            'after' => $after,
            'occurred_at' => now(),
        ]);
    }
}
