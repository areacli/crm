<?php

namespace App\Models;

use App\Enums\PartialPaymentPolicy;
use App\Enums\ReversalMonthPolicy;
use App\Enums\UpcomingDisplay;
use App\Enums\WithdrawnPaymentPolicy;
use App\Enums\WithdrawnReversalPolicy;
use Database\Factories\TenantSettingsFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Configuração do credor: faixas de atraso (R18) e tratamento do a vencer (R20). */
#[Table('tenant_settings')]
#[Fillable(['tenant_id', 'aging_brackets', 'upcoming_display', 'partial_payment_policy', 'withdrawn_payment_policy', 'withdrawn_reversal_policy', 'reversal_month_policy'])]
class TenantSettings extends Model
{
    /** @use HasFactory<TenantSettingsFactory> */
    use HasFactory;

    /** Faixas iniciais do sistema: [início, fim] em dias, a última aberta (fim nulo). */
    public const array DEFAULT_BRACKETS = [
        ['from' => 1, 'to' => 30],
        ['from' => 31, 'to' => 60],
        ['from' => 61, 'to' => 90],
        ['from' => 91, 'to' => 180],
        ['from' => 181, 'to' => 360],
        ['from' => 361, 'to' => null],
    ];

    protected function casts(): array
    {
        return [
            'aging_brackets' => 'array',
            'upcoming_display' => UpcomingDisplay::class,
            'partial_payment_policy' => PartialPaymentPolicy::class,
            'withdrawn_payment_policy' => WithdrawnPaymentPolicy::class,
            'withdrawn_reversal_policy' => WithdrawnReversalPolicy::class,
            'reversal_month_policy' => ReversalMonthPolicy::class,
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }
}
