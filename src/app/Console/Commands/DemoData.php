<?php

namespace App\Console\Commands;

use App\Enums\ImportMode;
use App\Import\ImportService;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Tenancy\TenantProvisioner;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

/**
 * Dados fictícios para a demonstração e as capturas de tela: um credor, um gestor e um operador, uma carteira
 * importada e uma importação conferida à espera de confirmação (com linhas recusadas). CPFs gerados, sem dono.
 */
#[Signature('crm:demo-data {--tenant=Escola Alfa : nome do credor} {--customers=60 : clientes da carteira}')]
#[Description('Cria o credor de demonstração com usuários, carteira fictícia e uma importação conferida')]
final class DemoData extends Command
{
    public function handle(TenantProvisioner $provisioner, ImportService $service): int
    {
        if (app()->isProduction()) {
            $this->error('Recusado em produção.');

            return self::FAILURE;
        }

        $tenant = Tenant::where('name', $this->option('tenant'))->first() ?? $provisioner->create((string) $this->option('tenant'));
        $manager = $this->user($tenant, 'gestor@demo.exemplo.com.br', 'Gestor', 'Gestor');
        $this->user($tenant, 'operador@demo.exemplo.com.br', 'Operador', 'Operador');

        $customers = (int) $this->option('customers');
        $csv = storage_path('app/demo-carteira.csv');
        $this->callSilent('crm:fake-csv', ['lines' => $customers * 2, 'path' => $csv, '--per-customer' => 2]);

        // Carteira inicial, confirmada.
        $import = $service->start($tenant, $manager, $csv, ImportMode::Incremental, 'carteira-outubro.csv');
        $service->confirm($import->refresh());

        // Segunda planilha, só conferida: com linhas recusadas, para mostrar a conferência e o botão de confirmar.
        $second = storage_path('app/demo-batimento.csv');
        $lines = file($csv, FILE_IGNORE_NEW_LINES);
        $header = array_shift($lines);
        $lines = array_slice($lines, 0, max(10, intdiv(count($lines), 2)));
        $lines[] = '111.111.111-11;Fulano de Tal;;;;NF-9001;10/09/2026;250,00;Documento com dígito errado';
        $lines[] = '529.982.247-25;Maria da Silva;;;CT-9;NF-9002;31/02/2026;250,00;Data inexistente';
        $lines[] = '390.533.447-05;João Souza;;;CT-9;NF-9003;10/09/2026;12,345;Valor com três casas';
        file_put_contents($second, $header."\n".implode("\n", $lines)."\n");
        $service->start($tenant, $manager, $second, ImportMode::FullSync, 'batimento-outubro.csv');

        @unlink($csv);
        @unlink($second);
        $this->info('Credor, usuários (senha: demonstracao-gestor e demonstracao-operador), carteira e uma importação conferida criados.');

        return self::SUCCESS;
    }

    private function user(Tenant $tenant, string $email, string $name, string $profile): User
    {
        $user = User::firstOrCreate(['email' => $email], ['name' => $name, 'password' => 'demonstracao-'.mb_strtolower($profile)]);
        Membership::firstOrCreate(
            ['user_id' => $user->id, 'tenant_id' => $tenant->id],
            ['profile_id' => Profile::where('tenant_id', $tenant->id)->where('name', $profile)->value('id')],
        );

        return $user;
    }
}
