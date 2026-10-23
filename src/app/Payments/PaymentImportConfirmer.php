<?php

namespace App\Payments;

use App\Enums\ImportStatus;
use App\Models\Import;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/** Confirmação da importação de pagamentos ou de estornos: aplica tudo numa única transação (R56, R63). */
final class PaymentImportConfirmer
{
    public function run(Import $import): void
    {
        $import->update(['status' => ImportStatus::Confirming, 'progress_percent' => 1, 'progress_label' => 'Gravando']);

        try {
            $effect = DB::transaction(function () use ($import) {
                // Uma importação por vez por credor, o mesmo bloqueio da carteira (R10).
                DB::select('select pg_advisory_xact_lock(?, ?)', [1, $import->tenant_id]);

                return $import->kind === 'reversals' ? (new ReversalProcessor)->run($import, true) : (new PaymentProcessor)->run($import, true);
            });
        } catch (\Throwable $e) {
            report($e);
            $import->update(['status' => ImportStatus::Failed, 'failure_reason' => class_basename($e), 'finished_at' => now(), 'progress_label' => null]);

            return;
        }

        foreach (['payments', 'credits', 'bills', 'payment_reversals'] as $table) {
            DB::statement("analyze $table");
        }
        DB::table('payment_rows')->where('import_id', $import->id)->delete();
        if ($import->stored_path) {
            Storage::disk('local')->delete($import->stored_path);
        }
        $summary = $import->summary ?? [];
        $summary['confirmed_effect'] = $effect;
        $import->update(['status' => ImportStatus::Confirmed, 'summary' => $summary, 'progress_percent' => 100, 'progress_label' => null, 'finished_at' => now()]);
    }
}
