<?php

namespace App\Console\Commands;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\ImportChecker;
use App\Import\ImportConfirmer;
use App\Import\ImportService;
use App\Models\Import;
use App\Models\Membership;
use App\Models\PaymentChannel;
use App\Models\Profile;
use App\Models\User;
use App\Payments\PaymentImportChecker;
use App\Payments\PaymentImportConfirmer;
use App\Portfolio\PortfolioQuery;
use App\Portfolio\PortfolioSummary;
use App\Support\FakeData;
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
#[Signature('crm:measure-import {lines=10000 : títulos da planilha} {--per-customer=2 : títulos por cliente (1 dá 200 mil clientes com 200 mil títulos)} {--payments : depois da carteira, mede 200 mil pagamentos e 20 mil estornos sobre ela (especificação 03)} {--keep : não apaga o credor de medição no fim}')]
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

        if ($this->option('payments')) {
            $this->measurePayments($tenant, $user, $lines, max(1, (int) $this->option('per-customer')));
        }

        @unlink($csv);
        if (! $this->option('keep')) {
            DB::table('import_rows')->where('import_id', $import->id)->delete();
            DB::table('credits')->where('tenant_id', $tenant->id)->delete();
            DB::table('payment_reversals')->where('tenant_id', $tenant->id)->delete();
            DB::table('payments')->where('tenant_id', $tenant->id)->delete();
            $user->delete();
            $tenant->delete();
            $this->line('credor de medição apagado');
        }

        return self::SUCCESS;
    }

    /** V4 da especificação 03: a conferência e a confirmação de pagamentos e de estornos, com os mesmos números da carteira. */
    private function measurePayments($tenant, $user, int $lines, int $per): void
    {
        PaymentChannel::create(['tenant_id' => $tenant->id, 'type' => 'account', 'code' => 'MEDICAO', 'description' => 'Canal de medição']);
        $path = storage_path('app/pagamentos-'.$tenant->id.'.csv');
        $out = fopen($path, 'wb');
        fwrite($out, "canal;identificador;documento;titulo;data_pagamento;valor;meio\n");
        for ($i = 0; $i < $lines; $i++) {
            $customer = intdiv($i, $per);
            $cents = 5000 + (($i * 7919) % 250_000);
            // 60% quitam, 20% pagam a metade, 10% pagam a mais, 10% citam um título que não existe (pendente).
            [$value, $number] = match ($i % 10) {
                0, 1, 2, 3, 4, 5 => [$cents, 'NF-'.$customer.'/'.($i % $per + 1)],
                6, 7 => [intdiv($cents, 2), 'NF-'.$customer.'/'.($i % $per + 1)],
                8 => [$cents + 1000, 'NF-'.$customer.'/'.($i % $per + 1)],
                default => [$cents, 'NF-X'.$i],
            };
            fwrite($out, implode(';', ['MEDICAO', 'PG'.$i, FakeData::cpf($customer), $number, now()->subDays($i % 30)->format('d/m/Y'), number_format($value / 100, 2, ',', '.'), 'pix'])."\n");
        }
        fclose($out);

        $import = $this->time('envio do arquivo de pagamentos', fn () => $this->startWithoutQueue($tenant, $user, $path, 'payments'));
        $this->time("conferência de {$lines} pagamentos", fn () => app(PaymentImportChecker::class)->run($import));
        $import->refresh();
        $this->line('  resumo: '.json_encode($import->summary['effect'] ?? null));
        $this->time("confirmação de {$lines} pagamentos", fn () => app(PaymentImportConfirmer::class)->run($import));
        $this->line('  situação: '.$import->refresh()->status->value.'; pagamentos gravados: '.DB::table('payments')->where('tenant_id', $tenant->id)->count());

        $reversals = max(1, intdiv($lines, 10));
        $path2 = storage_path('app/estornos-'.$tenant->id.'.csv');
        $out = fopen($path2, 'wb');
        fwrite($out, "canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo\n");
        for ($i = 0; $i < $reversals; $i++) {
            $source = $i * 10;
            fwrite($out, implode(';', ['MEDICAO', 'PG'.$source, 'ES'.$i, now()->format('d/m/Y'), number_format((5000 + (($source * 7919) % 250_000)) / 200 / 100, 2, ',', '.'), 'contestação'])."\n");
        }
        fclose($out);
        $import2 = $this->startWithoutQueue($tenant, $user, $path2, 'reversals');
        $this->time("conferência de {$reversals} estornos", fn () => app(PaymentImportChecker::class)->run($import2));
        $import2->refresh();
        $this->line('  resumo: '.json_encode($import2->summary['effect'] ?? null).' recusados: '.($import2->summary['rejected'] ?? '?'));
        $this->time("confirmação de {$reversals} estornos", fn () => app(PaymentImportConfirmer::class)->run($import2));
        $this->time('resumo da carteira com recebimentos', fn () => (new PortfolioSummary($user->fresh()))->perTenant());
        @unlink($path);
        @unlink($path2);
    }

    private function startWithoutQueue($tenant, $user, string $csv, string $kind = 'portfolio')
    {
        $path = 'imports/medicao-'.$tenant->id.'-'.$kind.'.csv';
        Storage::disk('local')->put($path, file_get_contents($csv));

        return Import::create([
            'tenant_id' => $tenant->id, 'user_id' => $user->id, 'kind' => $kind, 'mode' => ImportMode::Incremental,
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
