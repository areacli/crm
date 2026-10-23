<?php

namespace App\Console\Commands;

use App\Demo\DemoDataset;
use App\Demo\DemoMode;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * Recriação diária da demonstração pública (CRM_DEMO=1): apaga os credores e tudo o que depende deles, restaura os
 * usuários públicos e importa de novo a carteira e os recebimentos fictícios. Recusa fora do modo de demonstração.
 */
#[Signature('crm:demo-reset')]
#[Description('Recria os dados fictícios da demonstração pública (só com CRM_DEMO=1)')]
final class DemoReset extends Command
{
    public function handle(DemoDataset $dataset): int
    {
        if (! DemoMode::enabled()) {
            $this->error('Recusado: o modo de demonstração não está ligado (CRM_DEMO).');

            return self::FAILURE;
        }

        DB::transaction(function () {
            // Os credores levam junto, por chave estrangeira, importações, carteira, pagamentos, perfis, vínculos e registros.
            DB::statement('truncate table tenants restart identity cascade');
            DB::statement('truncate table import_rows, payment_rows, notifications');
        });

        $tenant = $dataset->create((string) config('crm.demo.tenant'), (int) config('crm.demo.customers'), DemoMode::domain(), public: true);
        $this->info("Demonstração recriada: {$tenant->name}.");

        return self::SUCCESS;
    }
}
