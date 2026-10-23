<?php

namespace App\Models;

use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Attributes\WithoutTimestamps;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;

/** Linha recusada na conferência, com o número da linha e o motivo. */
#[Fillable(['import_id', 'line', 'reason'])]
#[WithoutTimestamps]
class ImportRejection extends Model
{
    public function import(): BelongsTo
    {
        return $this->belongsTo(Import::class);
    }
}
