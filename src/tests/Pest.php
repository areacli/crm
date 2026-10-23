<?php

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\ImportService;
use App\Models\Bill;
use App\Models\Contract;
use App\Models\Customer;
use App\Models\Import;
use App\Models\Membership;
use App\Models\PaymentChannel;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\TenantSettings;
use App\Models\User;
use Illuminate\Foundation\Testing\RefreshDatabase;
use Tests\TestCase;

/*
| Os testes de regra (Unit) não tocam no banco; os de funcionalidade (Feature) usam o banco de testes
| (crm_test), recriado a cada execução.
*/
// Os testes de funcionalidade não precisam dos arquivos compilados pelo Vite (npm run build).
pest()->extend(TestCase::class)->use(RefreshDatabase::class)->beforeEach(fn () => $this->withoutVite())->in('Feature');
pest()->extend(TestCase::class)->in('Unit');
pest()->extend(TestCase::class)->use(RefreshDatabase::class)->in('Browser');

/** Credor com a configuração inicial e um perfil de gestor com todas as permissões, montados com as factories. */
function makeTenant(string $name = 'Escola Alfa'): Tenant
{
    $tenant = Tenant::factory()->create(['name' => $name]);
    TenantSettings::factory()->create(['tenant_id' => $tenant->id]);
    Profile::factory()->manager()->create(['tenant_id' => $tenant->id]);

    return $tenant;
}

function makeUser(Tenant $tenant, string $email = 'gestor@exemplo.com.br', string $profile = 'Gestor'): User
{
    $user = User::factory()->create(['email' => $email]);
    Membership::factory()->create([
        'user_id' => $user->id,
        'tenant_id' => $tenant->id,
        'profile_id' => Profile::where('tenant_id', $tenant->id)->where('name', $profile)->firstOrFail()->id,
    ]);

    return $user;
}

/** Grava um CSV de carteira num arquivo temporário e devolve o caminho. */
function portfolioCsv(array $lines): string
{
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    file_put_contents($path, "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n".implode("\n", $lines)."\n");

    return $path;
}

/** Cliente com títulos ativos já gravados (sem passar pela importação), para testar as consultas. */
function makeCustomerWithBills(Tenant $tenant, string $document, string $name, array $bills, ?string $contractCode = null): Customer
{
    $customer = Customer::factory()->create(['tenant_id' => $tenant->id, 'document' => $document, 'name' => $name]);
    $contract = $contractCode === null
        ? Contract::factory()->byOmission()->create(['tenant_id' => $tenant->id])
        : Contract::factory()->create(['tenant_id' => $tenant->id, 'code' => $contractCode]);
    $contract->customers()->attach($customer->id, ['roles' => json_encode(['holder', 'financial_responsible'])]);

    foreach ($bills as $number => [$due, $cents]) {
        Bill::factory()->create([
            'contract_id' => $contract->id, 'tenant_id' => $tenant->id, 'customer_id' => $customer->id,
            'number' => (string) $number, 'due_date' => $due, 'amount_cents' => $cents,
        ]);
    }

    return $customer;
}

/** Canal de recebimento do credor, montado com a factory. */
function makeChannel(Tenant $tenant, string $code = '341-1234-56789', bool $active = true): PaymentChannel
{
    return PaymentChannel::factory()->create(['tenant_id' => $tenant->id, 'code' => $code, 'active' => $active]);
}

/** Grava um CSV de pagamentos num arquivo temporário e devolve o caminho. */
function paymentsCsv(array $lines): string
{
    $path = tempnam(sys_get_temp_dir(), 'pagamentos');
    file_put_contents($path, "canal;identificador;documento;titulo;data_pagamento;valor;meio\n".implode("\n", $lines)."\n");

    return $path;
}

/** Grava um CSV de estornos num arquivo temporário e devolve o caminho. */
function reversalsCsv(array $lines): string
{
    $path = tempnam(sys_get_temp_dir(), 'estornos');
    file_put_contents($path, "canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo\n".implode("\n", $lines)."\n");

    return $path;
}

/** Envia um arquivo de pagamentos ou de estornos, confere e (se pedido) confirma; a fila é síncrona nos testes. */
function runPayments(Tenant $tenant, User $user, string $path, string $kind = 'payments', bool $confirm = true): Import
{
    $service = app(ImportService::class);
    $import = $service->start($tenant, $user, $path, ImportMode::Incremental, kind: $kind);
    if ($confirm && $import->status === ImportStatus::Checked) {
        $import = $service->confirm($import);
    }

    return $import;
}
