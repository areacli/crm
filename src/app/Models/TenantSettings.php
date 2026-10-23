<?php

namespace App\Models;

use App\Enums\UpcomingDisplay;
use Database\Factories\TenantSettingsFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\Table;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Configuração do credor: faixas de atraso (R18) e tratamento do a vencer (R20). */
#[Table('tenant_settings')]
#[Fillable(['tenant_id', 'aging_brackets', 'upcoming_display'])]
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
        ];
    }

    public function tenant(): BelongsTo
    {
        return $this->belongsTo(Tenant::class);
    }
}
