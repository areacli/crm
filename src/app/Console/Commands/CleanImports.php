<?php

namespace App\Console\Commands;

use App\Enums\ImportStatus;
use App\Models\Import;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Tarefa a cada 5 minutos (operação, O8): descarta a conferência abandonada há mais de 1 hora (R10) e marca como
 * "falhou" a importação presa há mais de 30 minutos, que libera o credor para uma nova importação (domínio, P5).
 * Só registra a execução quando faz algo, para não gravar 288 linhas por dia.
 */
#[Signature('crm:clean-imports')]
#[Description('Descarta conferências abandonadas e marca como falhas as importações presas')]
final class CleanImports extends Command
{
    public const int ABANDONED_AFTER_MINUTES = 60;

    public const int STUCK_AFTER_MINUTES = 30;

    public function handle(): int
    {
        $discarded = 0;
        $failed = 0;

        Import::query()
            ->where('status', ImportStatus::Checked)
            ->where('checked_at', '<', now()->subMinutes(self::ABANDONED_AFTER_MINUTES))
            ->each(function (Import $import) use (&$discarded) {
                $this->release($import);
                $import->update(['status' => ImportStatus::Discarded, 'finished_at' => now(), 'failure_reason' => 'conferência abandonada por mais de 1 hora']);
                $discarded++;
            });

        Import::query()
            ->whereIn('status', [ImportStatus::Received, ImportStatus::Checking, ImportStatus::Confirming])
            ->where('updated_at', '<', now()->subMinutes(self::STUCK_AFTER_MINUTES))
            ->each(function (Import $import) use (&$failed) {
                $this->release($import);
                $import->update(['status' => ImportStatus::Failed, 'finished_at' => now(), 'failure_reason' => 'tempo-limite: 30 minutos sem terminar', 'progress_label' => null]);
                $failed++;
            });

        if ($discarded + $failed > 0) {
            DB::table('task_runs')->insert([
                'task' => 'clean-imports', 'result' => 'done', 'ran_at' => now(),
                'details' => json_encode(['discarded' => $discarded, 'failed' => $failed]),
            ]);
        }
        $this->info("Descartadas: {$discarded}. Marcadas como falha: {$failed}.");

        return self::SUCCESS;
    }

    private function release(Import $import): void
    {
        DB::table('import_rows')->where('import_id', $import->id)->delete();
        if ($import->stored_path) {
            Storage::disk('local')->delete($import->stored_path);
        }
    }
}
