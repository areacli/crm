<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\WithoutTimestamps;
use Illuminate\Database\Eloquent\Model;

/** Histórico de alterações: só inserção, nunca alteração nem exclusão (grande regra 4). */
#[Fillable(['tenant_id', 'user_id', 'import_id', 'subject_type', 'subject_id', 'event', 'field', 'before', 'after', 'occurred_at'])]
#[WithoutTimestamps]
class Change extends Model
{
    protected function casts(): array
    {
        return ['occurred_at' => 'datetime'];
    }
}
