<?php

namespace App\Models;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Models\Concerns\BelongsToTenant;
use Database\Factories\ImportFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsTo;
use Illuminate\Database\Eloquent\Relations\HasMany;

/** Uma carga de arquivo, com conferência e confirmação (R10). */
#[Fillable(['tenant_id', 'user_id', 'kind', 'mode', 'status', 'original_name', 'stored_path', 'size_bytes', 'progress_percent', 'progress_label', 'summary', 'failure_reason', 'checked_at', 'finished_at'])]
class Import extends Model
{
    /** @use HasFactory<ImportFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return [
            'mode' => ImportMode::class,
            'status' => ImportStatus::class,
            'summary' => 'array',
            'checked_at' => 'datetime',
            'finished_at' => 'datetime',
        ];
    }

    public function user(): BelongsTo
    {
        return $this->belongsTo(User::class);
    }

    public function rejections(): HasMany
    {
        return $this->hasMany(ImportRejection::class);
    }
}
