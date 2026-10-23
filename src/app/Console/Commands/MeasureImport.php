<?php

namespace App\Console\Commands;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\ImportChecker;
use App\Import\ImportConfirmer;
use App\Import\ImportService;
use App\Models\Import;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\User;
use App\Portfolio\PortfolioQuery;
use App\Portfolio\PortfolioSummary;
use App\Tenancy\TenantProvisioner;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Medição com volume (V4): importa uma carteira fictícia e mede conferência, confirmação, lista e resumo.
 * Cria um credor de medição e o apaga no fim. Não use contra dados reais.
 */
#[Signature('crm:measure-import {lines=10000 : títulos da planilha} {--per-customer=2 : títulos por cliente (1 dá 200 mil clientes com 200 mil títulos)} {--keep : não apaga o credor de medição no fim}')]
#[Description('Mede conferência, confirmação, lista e resumo com uma carteira fictícia (V4)')]
final class MeasureImport extends Command
{
    public function handle(TenantProvisioner $provisioner, ImportService $service): int
    {
        if (app()->isProduction()) {
            $this->error('Recusado em produção.');

            return self::FAILURE;
        }

        $lines = (int) $this->argument('lines');
        $tenant = $provisioner->create('Medição '.now()->format('His'));
        $user = User::factory()->create(['email' => 'medicao'.$tenant->id.'@exemplo.com.br']);
        Membership::create(['user_id' => $user->id, 'tenant_id' => $tenant->id, 'profile_id' => Profile::where('tenant_id', $tenant->id)->where('name', 'Gestor')->value('id')]);

        $csv = storage_path('app/medicao-'.$tenant->id.'.csv');
        $this->callSilent('crm:fake-csv', ['lines' => $lines, 'path' => $csv, '--per-customer' => $this->option('per-customer')]);

        // Sem fila: roda cada etapa direto para medir o tempo de cada uma.
        config(['queue.default' => 'null']);
        $import = $this->time('envio e gravação do arquivo', fn () => $this->startWithoutQueue($tenant, $user, $csv));

        $this->time("conferência de {$lines} linhas", fn () => app(ImportChecker::class)->run($import));
        $import->refresh();
        $this->line('  resumo: '.json_encode(['valid' => $import->summary['valid'] ?? null, 'rejected' => $import->summary['rejected'] ?? null, 'customers' => $import->summary['customers'] ?? null]));

        // Perfil da confirmação: as consultas mais lentas, para ir ao EXPLAIN ANALYZE (decisão 0010).
        $slow = [];
        DB::listen(function ($query) use (&$slow) {
            $slow[] = [$query->time, preg_replace('/\s+/', ' ', substr($query->sql, 0, 110))];
        });
        $this->time("confirmação de {$lines} linhas", fn () => app(ImportConfirmer::class)->run($import));
        usort($slow, fn ($a, $b) => $b[0] <=> $a[0]);
        foreach (array_slice($slow, 0, 6) as [$ms, $sql]) {
            $this->line(sprintf('    %8.0f ms  %s', $ms, $sql));
        }
        $this->line('  situação: '.$import->refresh()->status->value);

        $query = new PortfolioQuery($user->fresh());
        $this->time('lista de clientes (primeira página)', fn () => $query->customers()->limit(25)->get());
        $this->time('lista de clientes (contagem total)', fn () => $query->customers()->count());
        $this->time('lista de clientes (busca por nome)', fn () => $query->customers('silva')->limit(25)->get());
        $this->time('resumo da carteira', fn () => (new PortfolioSummary($user->fresh()))->perTenant());

        @unlink($csv);
        if (! $this->option('keep')) {
            DB::table('import_rows')->where('import_id', $import->id)->delete();
            $user->delete();
            $tenant->delete();
            $this->line('credor de medição apagado');
        }

        return self::SUCCESS;
    }

    private function startWithoutQueue($tenant, $user, string $csv)
    {
        $path = 'imports/medicao-'.$tenant->id.'.csv';
        Storage::disk('local')->put($path, file_get_contents($csv));

        return Import::create([
            'tenant_id' => $tenant->id, 'user_id' => $user->id, 'kind' => 'portfolio', 'mode' => ImportMode::Incremental,
            'status' => ImportStatus::Received, 'original_name' => 'medicao.csv', 'stored_path' => $path,
            'size_bytes' => Storage::disk('local')->size($path),
        ]);
    }

    private function time(string $label, callable $work): mixed
    {
        $start = microtime(true);
        $result = $work();
        $this->line(sprintf('%-45s %8.2f s   (pico de memória %d MB)', $label, microtime(true) - $start, memory_get_peak_usage(true) / 1048576));

        return $result;
    }
}
