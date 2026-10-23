<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Database\Factories\CustomerFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Cliente do credor (antes "devedor"): único por credor, pelo documento sem máscara (MT-9). */
#[Fillable(['tenant_id', 'document', 'name', 'phone', 'email'])]
class Customer extends Model
{
    /** @use HasFactory<CustomerFactory> */
    use BelongsToTenant, HasFactory;

    public function contracts(): BelongsToMany
    {
        return $this->belongsToMany(Contract::class)->withPivot('roles');
    }

    public function bills(): HasMany
    {
        return $this->hasMany(Bill::class);
    }
}
