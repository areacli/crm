<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Estorno de um pagamento (R60 a R64). */
#[Fillable(['tenant_id', 'channel_id', 'payment_id', 'import_id', 'identifier', 'reversed_on', 'amount_cents', 'from_credit_cents', 'from_bill_cents', 'reason'])]
class PaymentReversal extends Model
{
    use BelongsToTenant;

    protected function casts(): array
    {
        return ['reversed_on' => 'date'];
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }
}
