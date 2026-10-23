<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Database\Factories\MembershipFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Vínculo de um usuário com um credor, com o perfil dele ali (MT-2). */
#[Fillable(['user_id', 'tenant_id', 'profile_id', 'active'])]
class Membership extends Model
{
    /** @use HasFactory<MembershipFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['active' => 'boolean'];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function profile(): BelongsTo
    {
        return $this->belongsTo(Profile::class);
    }
}
