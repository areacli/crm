<?php

namespace App\Models;

use App\Enums\ContactResultType;
use App\Enums\ReturnRule;
use App\Models\Concerns\BelongsToTenant;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Resultado de acionamento do credor: nome livre, tipo fixo e regra de retorno (R66). */
#[Fillable(['tenant_id', 'name', 'type', 'return_rule', 'active', 'position'])]
class ContactResult extends Model
{
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['type' => ContactResultType::class, 'return_rule' => ReturnRule::class, 'active' => 'boolean'];
    }

    public function attempts(): HasMany
    {
        return $this->hasMany(ContactAttempt::class, 'result_id');
    }
}
