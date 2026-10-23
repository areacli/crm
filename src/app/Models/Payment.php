<?php

namespace App\Models;

use App\Enums\PaymentMethod;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\PaymentFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Pagamento recebido por um canal, sempre de um título (MT-22); pendente se o título ainda não está na carteira. */
#[Fillable(['tenant_id', 'channel_id', 'import_id', 'identifier', 'document', 'bill_number', 'bill_id', 'paid_on', 'amount_cents', 'method', 'status', 'applied_cents', 'credit_cents', 'reversed_cents', 'credit_reversed_cents'])]
class Payment extends Model
{
    /** @use HasFactory<PaymentFactory> */
    use BelongsToTenant, HasFactory;

    public const string APPLIED = 'applied';

    public const string PENDING = 'pending';

    protected function casts(): array
    {
        return ['paid_on' => 'date', 'method' => PaymentMethod::class, 'amount_cents' => 'integer'];
    }

    public function channel(): BelongsTo
    {
        return $this->belongsTo(PaymentChannel::class, 'channel_id');
    }

    public function bill(): BelongsTo
    {
        return $this->belongsTo(Bill::class);
    }

    public function reversals(): HasMany
    {
        return $this->hasMany(PaymentReversal::class);
    }

    /** O que ainda pode ser estornado (R61). */
    public function reversibleCents(): int
    {
        return $this->amount_cents - $this->reversed_cents;
    }
}
