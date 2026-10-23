<?php

namespace App\Models;

use App\Enums\BillStatus;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\BillFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Support\Carbon;

/** Título: uma obrigação a pagar (parcela, mensalidade, fatura), sempre dentro de um contrato. */
#[Fillable(['tenant_id', 'contract_id', 'customer_id', 'number', 'due_date', 'amount_cents', 'paid_cents', 'paid_on', 'description', 'status', 'last_import_id', 'withdrawn_import_id', 'withdrawn_at'])]
class Bill extends Model
{
    /** @use HasFactory<BillFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'due_date' => 'date',
            'amount_cents' => 'integer',
            'paid_cents' => 'integer',
            'paid_on' => 'date',
            'status' => BillStatus::class,
            'withdrawn_at' => 'datetime',
        ];
    }

    public function contract(): BelongsTo
    {
        return $this->belongsTo(Contract::class);
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    /** Saldo do título: valor menos o que já foi pago (R54). */
    public function balanceCents(): int
    {
        return $this->amount_cents - $this->paid_cents;
    }

    /** Dias de atraso em relação à data de referência; zero ou negativo quando a vencer (R17). */
    public function daysOverdue(Carbon $reference): int
    {
        return (int) $this->due_date->startOfDay()->diffInDays($reference->copy()->startOfDay(), false);
    }
}
