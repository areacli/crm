<?php

namespace App\Demo;

use App\Enums\ContactChannel;
use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Import\ImportService;
use App\Models\ContactResult;
use App\Models\Customer;
use App\Models\Membership;
use App\Models\PaymentChannel;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Support\FakeData;
use App\Tenancy\TenantProvisioner;
use Illuminate\Support\Facades\Artisan;
use Illuminate\Support\Facades\DB;

/**
 * Dados fictícios da demonstração e das capturas de tela: um credor, usuários, carteira, recebimentos e uma importação
 * conferida à espera de confirmação (com linhas recusadas). CPFs gerados, sem dono. Na demonstração pública
 * (`$public`), o gestor tem o perfil "Gestor demonstração": todas as permissões, menos gerenciar usuários e perfis.
 */
final class DemoDataset
{
    public function __construct(private readonly TenantProvisioner $provisioner, private readonly ImportService $service) {}

    public function create(string $tenantName, int $customers, string $domain, bool $public = false): Tenant
    {
        // As conferências e confirmações precisam terminar antes do passo seguinte: roda sem fila, na própria execução.
        $queue = config('queue.default');
        config(['queue.default' => 'sync']);

        try {
            return $this->build($tenantName, $customers, $domain, $public);
        } finally {
            config(['queue.default' => $queue]);
        }
    }

    private function build(string $tenantName, int $customers, string $domain, bool $public): Tenant
    {
        $tenant = Tenant::where('name', $tenantName)->first() ?? $this->provisioner->create($tenantName);
        $profile = 'Gestor';
        if ($public) {
            $profile = 'Gestor demonstração';
            Profile::updateOrCreate(
                ['tenant_id' => $tenant->id, 'name' => $profile],
                ['permissions' => array_values(array_map(fn (Permission $p) => $p->value, array_filter(Permission::cases(), fn (Permission $p) => ! in_array($p, [Permission::ManageUsers, Permission::ManageProfiles], true))))],
            );
        }
        $manager = $this->user($tenant, 'gestor@'.$domain, 'Gestor', $profile, 'demonstracao-gestor');
        $this->user($tenant, 'operador@'.$domain, 'Operador', 'Operador', 'demonstracao-operador');

        $csv = storage_path('app/demo-carteira.csv');
        Artisan::call('crm:fake-csv', ['lines' => $customers * 2, 'path' => $csv, '--per-customer' => 2]);

        // Carteira inicial, confirmada.
        $import = $this->service->start($tenant, $manager, $csv, ImportMode::Incremental, 'carteira-outubro.csv');
        $this->service->confirm($import->refresh());

        $this->payments($tenant, $manager, $customers);
        $this->contactAttempts($tenant, [$manager->id, User::where('email', 'operador@'.$domain)->value('id')], $customers);

        // Segunda planilha, só conferida: com linhas recusadas, para mostrar a conferência e o botão de confirmar.
        $second = storage_path('app/demo-batimento.csv');
        $lines = file($csv, FILE_IGNORE_NEW_LINES);
        $header = array_shift($lines);
        $lines = array_slice($lines, 0, max(10, intdiv(count($lines), 2)));
        $lines[] = '111.111.111-11;Fulano de Tal;;;;NF-9001;10/09/2026;250,00;Documento com dígito errado';
        $lines[] = '529.982.247-25;Maria da Silva;;;CT-9;NF-9002;31/02/2026;250,00;Data inexistente';
        $lines[] = '390.533.447-05;João Souza;;;CT-9;NF-9003;10/09/2026;12,345;Valor com três casas';
        file_put_contents($second, $header."\n".implode("\n", $lines)."\n");
        $this->service->start($tenant, $manager, $second, ImportMode::FullSync, 'batimento-outubro.csv');

        @unlink($csv);
        @unlink($second);

        return $tenant;
    }

    /**
     * Recebimentos fictícios: três canais, pagamentos quitando, parciais e a mais, um título pago duas vezes, pagamentos
     * de título que não existe (pendentes) e alguns estornos. A importação de pagamentos fica confirmada.
     */
    private function payments(Tenant $tenant, User $manager, int $customers): void
    {
        foreach ([['account', '341-1234-56789', 'Itaú, conta principal'], ['agreement', '2847193', 'Convênio de cobrança, Bradesco'], ['card', '1029384756', 'Cielo, loja virtual']] as [$type, $code, $description]) {
            PaymentChannel::firstOrCreate(['tenant_id' => $tenant->id, 'code' => $code], ['type' => $type, 'description' => $description]);
        }

        $rows = ['canal;identificador;documento;titulo;data_pagamento;valor;meio'];
        $methods = ['pix' => '341-1234-56789', 'boleto' => '2847193', 'cartão de crédito' => '1029384756'];
        $methodNames = array_keys($methods);
        for ($i = 0; $i < $customers * 2; $i++) {
            $customer = intdiv($i, 2);
            $cents = 5000 + (($i * 7919) % 250_000);
            [$value, $number] = match ($i % 10) {
                0, 1, 2, 3 => [$cents, 'NF-'.$customer.'/'.($i % 2 + 1)],
                4, 5 => [intdiv($cents, 2), 'NF-'.$customer.'/'.($i % 2 + 1)],
                6 => [$cents + 2500, 'NF-'.$customer.'/'.($i % 2 + 1)],
                default => [0, null],
            };
            if ($number === null) {
                continue;
            }
            $method = $methodNames[$i % 3];
            $rows[] = implode(';', [$methods[$method], 'DEMO'.$i, FakeData::cpf($customer), $number, now()->subDays($i % 20)->format('d/m/Y'), number_format($value / 100, 2, ',', '.'), $method]);
        }
        $rows[] = implode(';', ['341-1234-56789', 'DEMO-DUP', FakeData::cpf(0), 'NF-0/1', now()->format('d/m/Y'), '100,00', 'pix']);
        $rows[] = implode(';', ['341-1234-56789', 'DEMO-PEND1', FakeData::cpf(1), 'NF-9100/1', now()->format('d/m/Y'), '300,00', 'pix']);
        $rows[] = implode(';', ['2847193', 'DEMO-PEND2', FakeData::cpf(2), 'NF-9101/1', now()->format('d/m/Y'), '450,00', 'boleto']);
        $file = storage_path('app/demo-pagamentos.csv');
        file_put_contents($file, implode("\n", $rows)."\n");
        $import = $this->service->start($tenant, $manager, $file, ImportMode::Incremental, 'pagamentos-outubro.csv', 'payments');
        $this->service->confirm($import->refresh());

        $reversals = ['canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo'];
        foreach ([0, 10, 20] as $n) {
            $cents = 5000 + (($n * 7919) % 250_000);
            $reversals[] = implode(';', [$methods[$methodNames[$n % 3]], 'DEMO'.$n, 'DEMO-EST'.$n, now()->format('d/m/Y'), number_format(intdiv($cents, 3) / 100, 2, ',', '.'), 'contestação do pagador']);
        }
        $file2 = storage_path('app/demo-estornos.csv');
        file_put_contents($file2, implode("\n", $reversals)."\n");
        $second = $this->service->start($tenant, $manager, $file2, ImportMode::Incremental, 'estornos-outubro.csv', 'reversals');
        $this->service->confirm($second->refresh());
        @unlink($file);
        @unlink($file2);
    }

    /**
     * Acionamentos fictícios dos últimos 30 dias, distribuídos entre os resultados, os canais e os dois usuários, para a lista e
     * o resumo terem conteúdo; os textos são fixos. Três por cliente em média, com alguns anulados.
     *
     * @param  list<int>  $userIds
     */
    private function contactAttempts(Tenant $tenant, array $userIds, int $customers): void
    {
        $results = ContactResult::query()->where('tenant_id', $tenant->id)->orderBy('position')->get();
        $customerIds = Customer::query()->where('tenant_id', $tenant->id)->orderBy('id')->pluck('id')->all();
        $channels = ContactChannel::cases();
        $rows = [];
        $total = $customers * 3;
        for ($i = 0; $i < $total; $i++) {
            $result = $results[$i % count($results)];
            $when = now()->subDays($i % 30)->subMinutes(($i * 37) % 600);
            $rows[] = [
                'tenant_id' => $tenant->id, 'customer_id' => $customerIds[($i * 7) % count($customerIds)], 'user_id' => $userIds[$i % count($userIds)],
                'result_id' => $result->id, 'result_type' => $result->type->value, 'channel' => $channels[$i % 5]->value,
                'text' => $i % 4 === 0 ? 'texto da demonstração' : null, 'contacted_at' => $when,
                'return_at' => $result->return_rule === ReturnRule::Required ? $when->copy()->addDays(3) : null,
                'voided_at' => $i % 40 === 0 ? $when : null, 'voided_by' => $i % 40 === 0 ? $userIds[0] : null, 'void_reason' => $i % 40 === 0 ? 'registrado por engano' : null,
                'created_at' => $when, 'updated_at' => $when,
            ];
            if (count($rows) >= 1000) {
                DB::table('contact_attempts')->insert($rows);
                $rows = [];
            }
        }
        if ($rows !== []) {
            DB::table('contact_attempts')->insert($rows);
        }
    }

    private function user(Tenant $tenant, string $email, string $name, string $profile, string $password): User
    {
        $user = User::firstOrCreate(['email' => $email], ['name' => $name, 'password' => $password]);
        // Senhas públicas e legíveis: a recriação diária as restaura e tira qualquer bloqueio.
        $user->forceFill(['password' => $password, 'active' => true, 'failed_attempts' => 0, 'locked_until' => null, 'temporary_password_until' => null])->save();
        Membership::updateOrCreate(
            ['user_id' => $user->id, 'tenant_id' => $tenant->id],
            ['profile_id' => Profile::where('tenant_id', $tenant->id)->where('name', $profile)->value('id'), 'active' => true],
        );

        return $user;
    }
}
