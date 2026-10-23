<?php

namespace App\Import;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Jobs\CheckImport;
use App\Jobs\ConfirmImport;
use App\Models\Import;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;
use Illuminate\Support\Str;

/** Ciclo da importação de carteira: enviar, conferir, confirmar ou descartar. */
final class ImportService
{
    /** @throws ImportRefused quando já há uma importação em andamento no credor (R10, caso de exceção). */
    public function start(Tenant $tenant, User $user, UploadedFile|string $file, ImportMode $mode, ?string $originalName = null, string $kind = 'portfolio'): Import
    {
        if ($this->inProgress($tenant) !== null) {
            throw new ImportRefused('há uma importação em andamento');
        }

        $name = Str::uuid().'.csv';
        $path = 'imports/'.$name;
        if ($file instanceof UploadedFile) {
            $originalName ??= $file->getClientOriginalName();
            Storage::disk('local')->putFileAs('imports', $file, $name);
        } else {
            $originalName ??= basename($file);
            Storage::disk('local')->put($path, file_get_contents($file));
        }

        $import = Import::create([
            'tenant_id' => $tenant->id,
            'user_id' => $user->id,
            'kind' => $kind,
            'mode' => $mode,
            'status' => ImportStatus::Received,
            'original_name' => $originalName,
            'stored_path' => $path,
            'size_bytes' => Storage::disk('local')->size($path),
        ]);

        CheckImport::dispatch($import);

        return $import->refresh();
    }

    public function confirm(Import $import): Import
    {
        if ($import->status !== ImportStatus::Checked) {
            throw new ImportRefused('só uma importação conferida pode ser confirmada');
        }
        $import->update(['status' => ImportStatus::Confirming, 'progress_percent' => 0]);
        ConfirmImport::dispatch($import);

        return $import->refresh();
    }

    public function discard(Import $import): Import
    {
        if ($import->status !== ImportStatus::Checked) {
            throw new ImportRefused('só uma importação conferida pode ser descartada');
        }
        DB::table($import->kind === 'portfolio' ? 'import_rows' : 'payment_rows')->where('import_id', $import->id)->delete();
        Storage::disk('local')->delete($import->stored_path);
        $import->update(['status' => ImportStatus::Discarded, 'finished_at' => now()]);

        return $import->refresh();
    }

    public function inProgress(Tenant $tenant): ?Import
    {
        return Import::query()
            ->where('tenant_id', $tenant->id)
            ->whereIn('status', collect(ImportStatus::cases())->filter->isInProgress()->map->value->all())
            ->first();
    }
}
