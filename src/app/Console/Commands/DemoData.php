<?php

namespace App\Console\Commands;

use App\Demo\DemoDataset;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

/**
 * Dados fictícios para o desenvolvimento e as capturas de tela: um credor, um gestor e um operador, uma carteira
 * importada, recebimentos e uma importação conferida à espera de confirmação (com linhas recusadas).
 */
#[Signature('crm:demo-data {--tenant=Escola Alfa : nome do credor} {--customers=60 : clientes da carteira}')]
#[Description('Cria o credor de demonstração com usuários, carteira fictícia, recebimentos e uma importação conferida')]
final class DemoData extends Command
{
    public function handle(DemoDataset $dataset): int
    {
        if (app()->isProduction()) {
            $this->error('Recusado em produção. Na demonstração pública, use crm:demo-reset.');

            return self::FAILURE;
        }

        $dataset->create((string) $this->option('tenant'), (int) $this->option('customers'), 'demo.exemplo.com.br');
        $this->info('Credor, usuários (senha: demonstracao-gestor e demonstracao-operador), carteira, recebimentos e uma importação conferida criados.');

        return self::SUCCESS;
    }
}
