<?php

namespace App\Models;

use App\Enums\ContactChannel;
use App\Enums\ContactResultType;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Acionamento: uma tentativa de contato com um cliente (R69). Só inserção, mais a anulação (R75). */
#[Fillable(['tenant_id', 'customer_id', 'contract_id', 'user_id', 'result_id', 'result_type', 'channel', 'contact_used', 'text', 'contacted_at', 'return_at', 'voided_at', 'voided_by', 'void_reason'])]
class ContactAttempt extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'channel' => ContactChannel::class,
            'result_type' => ContactResultType::class,
            'contacted_at' => 'datetime',
            'return_at' => 'datetime',
            'voided_at' => 'datetime',
        ];
    }

    public function customer(): BelongsTo
    {
        return $this->belongsTo(Customer::class);
    }

    public function contract(): BelongsTo
    {
        return $this->belongsTo(Contract::class);
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function voidedBy(): BelongsTo
    {
        return $this->belongsTo(User::class, 'voided_by');
    }

    public function result(): BelongsTo
    {
        return $this->belongsTo(ContactResult::class, 'result_id');
    }

    public function isVoided(): bool
    {
        return $this->voided_at !== null;
    }
}
