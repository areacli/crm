<?php

namespace App\Models;

use App\Enums\ChannelType;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\PaymentChannelFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Canal de recebimento do credor: por onde o dinheiro entrou (R45). */
#[Fillable(['tenant_id', 'type', 'code', 'description', 'active'])]
class PaymentChannel extends Model
{
    /** @use HasFactory<PaymentChannelFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['type' => ChannelType::class, 'active' => 'boolean'];
    }

    public function payments(): HasMany
    {
        return $this->hasMany(Payment::class, 'channel_id');
    }
}
