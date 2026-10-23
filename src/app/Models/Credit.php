<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\WithoutTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Lançamento de crédito do contrato (MT-22): só inserção; o saldo do crédito é a soma dos lançamentos. */
#[WithoutTimestamps]
#[Fillable(['tenant_id', 'contract_id', 'payment_id', 'user_id', 'kind', 'amount_cents', 'reason', 'note', 'related_contract_id', 'occurred_at'])]
class Credit extends Model
{
    use BelongsToTenant;

    public const string ENTRY = 'entry';

    public const string REVERSAL = 'reversal';

    public const string TRANSFER_OUT = 'transfer_out';

    public const string TRANSFER_IN = 'transfer_in';

    protected function casts(): array
    {
        return ['occurred_at' => 'datetime', 'amount_cents' => 'integer'];
    }

    public function contract(): BelongsTo
    {
        return $this->belongsTo(Contract::class);
    }

    public function payment(): BelongsTo
    {
        return $this->belongsTo(Payment::class);
    }
}
