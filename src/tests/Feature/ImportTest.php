<?php

use App\Enums\BillStatus;
use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Models\Bill;
use App\Models\Change;
use App\Models\Contract;
use App\Models\Customer;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

beforeEach(function () {
    Storage::fake('local');
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->service = app(ImportService::class);
});

function runImport($test, array $lines, ImportMode $mode = ImportMode::Incremental, bool $confirm = true)
{
    $import = $test->service->start($test->tenant, $test->user, portfolioCsv($lines), $mode);
    if ($confirm && $import->status === ImportStatus::Checked) {
        $import = $test->service->confirm($import);
    }

    return $import->refresh();
}

// Critério: arquivo com 5 linhas válidas de 3 devedores -> a conferência mostra 3 clientes, 5 títulos e a soma exata, sem gravar nada.
it('confere sem gravar nada na carteira', function () {
    $import = runImport($this, [
        '529.982.247-25;Maria da Silva;;;CT-1;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria da Silva;;;CT-1;NF-2;10/10/2026;200,50;',
        '11.222.333/0001-81;Empresa X;;;;NF-3;10/09/2026;300,00;',
        '390.533.447-05;João Souza;;;;NF-4;10/09/2026;400,00;',
        '390.533.447-05;João Souza;;;;NF-5;10/09/2026;0,50;',
    ], confirm: false);

    expect($import->status)->toBe(ImportStatus::Checked)
        ->and($import->summary['customers'])->toBe(3)
        ->and($import->summary['valid'])->toBe(5)
        ->and($import->summary['amount_cents'])->toBe(10000 + 20050 + 30000 + 40000 + 50)
        ->and(Bill::count())->toBe(0)
        ->and(Customer::count())->toBe(0);
});

it('confirma e grava clientes, contratos e títulos', function () {
    $import = runImport($this, [
        '529.982.247-25;Maria da Silva;;;CT-1;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria da Silva;;;CT-1;NF-2;10/10/2026;200,50;',
        '390.533.447-05;João Souza;;;;NF-4;10/09/2026;400,00;',
    ]);

    expect($import->status)->toBe(ImportStatus::Confirmed)
        ->and(Customer::count())->toBe(2)
        ->and(Bill::count())->toBe(3)
        ->and((int) Bill::sum('amount_cents'))->toBe(70050);
});

// MT-11: todo título tem contrato. Com contrato declarado, os títulos se agrupam nele (R9).
it('agrupa os títulos pelo contrato declarado', function () {
    runImport($this, [
        '529.982.247-25;Maria;;;CT-1;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;CT-1;NF-2;10/10/2026;100,00;',
        '529.982.247-25;Maria;;;CT-1;NF-3;10/11/2026;100,00;',
        '529.982.247-25;Maria;;;;NF-9;10/09/2026;100,00;',
    ]);

    $contract = Contract::where('code', 'CT-1')->firstOrFail();
    expect($contract->bills()->count())->toBe(3)
        ->and(Bill::whereNull('contract_id')->count())->toBe(0);
});

// MT-14: a omissão cria um contrato por cliente, e as cargas seguintes o reaproveitam.
it('cria um contrato por cliente quando a planilha omite o contrato e o reaproveita depois', function () {
    runImport($this, [
        '529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;',
        '390.533.447-05;João;;;;NF-2;10/09/2026;100,00;',
    ]);
    expect(Contract::where('created_by_omission', true)->count())->toBe(2);

    runImport($this, ['529.982.247-25;Maria;;;;NF-3;10/09/2026;100,00;']);
    expect(Contract::where('created_by_omission', true)->count())->toBe(2)
        ->and(Customer::where('document', '52998224725')->first()->bills()->count())->toBe(2);
});

it('informa na conferência quantos contratos serão criados por omissão', function () {
    $import = runImport($this, [
        '529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;NF-2;10/09/2026;100,00;',
        '390.533.447-05;João;;;;NF-3;10/09/2026;100,00;',
    ], confirm: false);

    expect($import->summary['contracts_created_by_omission'])->toBe(2);
});

// Critério: CPF 111.111.111-11 -> linha recusada com número da linha e motivo; as demais seguem válidas.
it('recusa a linha com CPF inválido e mantém as demais', function () {
    $import = runImport($this, [
        '529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;',
        '111.111.111-11;Fulano;;;;NF-2;10/09/2026;100,00;',
    ], confirm: false);

    $rejection = $import->rejections()->first();
    expect($import->summary['valid'])->toBe(1)
        ->and($rejection->line)->toBe(3)
        ->and($rejection->reason)->toBe('CPF inválido');
});

// R4: o mesmo título repetido no arquivo: a primeira vale, a seguinte é recusada.
it('recusa o título repetido no arquivo, citando a primeira linha', function () {
    $import = runImport($this, [
        '529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;NF-1;10/09/2026;999,00;',
    ], confirm: false);

    expect($import->rejections()->first()->reason)->toBe('título repetido na linha 2')
        ->and($import->summary['valid'])->toBe(1);
});

// R7: nomes iguais depois de normalizar -> aceitas; nomes diferentes -> todas as linhas do documento recusadas.
it('aceita o mesmo nome com maiúsculas e espaços diferentes', function () {
    $import = runImport($this, [
        '529.982.247-25;MARIA  DA SILVA;;;;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria da Silva;;;;NF-2;10/09/2026;100,00;',
    ], confirm: false);

    expect($import->summary['valid'])->toBe(2)->and($import->rejections()->count())->toBe(0);
});

it('recusa todas as linhas do documento quando os nomes divergem', function () {
    $import = runImport($this, [
        '390.533.447-05;João;;;;NF-0;10/09/2026;100,00;',
        '529.982.247-25;Maria da Silva;;;;NF-1;10/09/2026;100,00;',
        '529.982.247-25;Maria Silva;;;;NF-2;10/09/2026;100,00;',
    ], confirm: false);

    expect($import->summary['valid'])->toBe(1)
        ->and($import->rejections()->count())->toBe(2)
        ->and($import->rejections()->first()->reason)->toBe('nomes diferentes para o mesmo documento: linhas 3 e 4');
});

// Critério: incremental -> A, B, C, D ativos, nenhum retirado.
it('no modo incremental não retira ninguém', function () {
    runImport($this, [
        '529.982.247-25;Maria;;;;A;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;B;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;C;10/09/2026;100,00;',
    ]);
    runImport($this, [
        '529.982.247-25;Maria;;;;B;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;D;10/09/2026;100,00;',
    ]);

    expect(Bill::where('status', BillStatus::Active)->count())->toBe(4)
        ->and(Bill::where('status', BillStatus::Withdrawn)->count())->toBe(0);
});

// Critério: batimento -> a conferência informa A e C a retirar; ao confirmar, ficam retirados.
it('no batimento informa e retira os títulos ausentes', function () {
    runImport($this, [
        '529.982.247-25;Maria;;;;A;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;B;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;C;10/09/2026;300,00;',
    ]);

    $import = runImport($this, [
        '529.982.247-25;Maria;;;;B;10/09/2026;100,00;',
        '529.982.247-25;Maria;;;;D;10/09/2026;100,00;',
    ], ImportMode::FullSync, confirm: false);

    expect($import->summary['to_withdraw'])->toBe(['count' => 2, 'amount_cents' => 40000]);

    $this->service->confirm($import);
    $withdrawn = Bill::where('status', BillStatus::Withdrawn)->orderBy('number')->get();
    expect($withdrawn->pluck('number')->all())->toBe(['A', 'C'])
        ->and($withdrawn->first()->withdrawn_at)->not->toBeNull()
        ->and(Change::where('event', 'withdrawn')->count())->toBe(2);
});

// R15: título gravado cuja linha foi recusada não é retirado no batimento.
it('não retira o título cuja linha foi recusada no batimento', function () {
    runImport($this, ['529.982.247-25;Maria;;;;A;10/09/2026;100,00;']);

    $import = runImport($this, [
        '529.982.247-25;Maria;;;;A;31/02/2026;100,00;',
        '390.533.447-05;João;;;;Z;10/09/2026;100,00;',
    ], ImportMode::FullSync, confirm: false);

    expect($import->summary['to_withdraw']['count'])->toBe(0)
        ->and($import->summary['kept_by_rejection'])->toBe(1);

    $this->service->confirm($import);
    expect(Bill::where('number', 'A')->first()->status)->toBe(BillStatus::Active);
});

it('não retira nenhum título do documento recusado por nomes divergentes', function () {
    runImport($this, [
        '529.982.247-25;Maria da Silva;;;;A;10/09/2026;100,00;',
        '529.982.247-25;Maria da Silva;;;;B;10/09/2026;100,00;',
    ]);
    $import = runImport($this, [
        '529.982.247-25;Maria da Silva;;;;A;10/09/2026;100,00;',
        '529.982.247-25;Maria Silva;;;;A2;10/09/2026;100,00;',
        '390.533.447-05;João;;;;Z;10/09/2026;100,00;',
    ], ImportMode::FullSync);

    expect(Bill::where('status', BillStatus::Withdrawn)->count())->toBe(0);
});

// R16: título retirado que volta fica ativo, com o histórico das duas datas.
it('reinclui o título retirado e registra', function () {
    runImport($this, ['529.982.247-25;Maria;;;;A;10/09/2026;100,00;', '529.982.247-25;Maria;;;;B;10/09/2026;100,00;']);
    runImport($this, ['529.982.247-25;Maria;;;;B;10/09/2026;100,00;'], ImportMode::FullSync);
    expect(Bill::where('number', 'A')->first()->status)->toBe(BillStatus::Withdrawn);

    $import = runImport($this, ['529.982.247-25;Maria;;;;A;10/09/2026;100,00;'], confirm: false);
    expect($import->summary['bills_reincluded'])->toBe(1);
    $this->service->confirm($import);

    $bill = Bill::where('number', 'A')->first();
    expect($bill->status)->toBe(BillStatus::Active)
        ->and($bill->withdrawn_at)->toBeNull()
        ->and(Change::where('subject_id', $bill->id)->pluck('event')->all())->toContain('withdrawn', 'reincluded');
});

// R13: reimportação atualiza o título existente, sem duplicar, e registra a mudança.
it('atualiza valor e vencimento sem duplicar e registra a alteração', function () {
    runImport($this, ['529.982.247-25;Maria;;;;NF-1024/3;10/09/2026;100,00;']);
    runImport($this, ['529.982.247-25;Maria;;;;NF-1024/3;10/10/2026;120,00;']);

    $bill = Bill::firstOrFail();
    expect(Bill::count())->toBe(1)
        ->and($bill->amount_cents)->toBe(12000)
        ->and(Change::where('subject_id', $bill->id)->where('field', 'amount_cents')->first()->only(['before', 'after']))
        ->toBe(['before' => '10000', 'after' => '12000'])
        ->and(Change::where('subject_id', $bill->id)->where('field', 'due_date')->exists())->toBeTrue();
});

// R8: nome muda e fica registrado; telefone vazio na carga nova não apaga o anterior.
it('atualiza o nome com registro e mantém o telefone quando a carga vem sem', function () {
    runImport($this, ['529.982.247-25;Maria da Silva;(11) 98765-4321;;;NF-1;10/09/2026;100,00;']);
    runImport($this, ['529.982.247-25;Maria da Silva Souza;;;;NF-2;10/09/2026;100,00;']);

    $customer = Customer::firstOrFail();
    expect($customer->name)->toBe('Maria da Silva Souza')
        ->and($customer->phone)->toBe('(11) 98765-4321')
        ->and(Change::where('subject_type', 'customer')->where('field', 'name')->count())->toBe(1)
        ->and(Change::where('subject_type', 'customer')->where('field', 'phone')->count())->toBe(0);
});

it('é único por credor: o mesmo documento em outro credor é outro cliente', function () {
    runImport($this, ['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']);

    $other = makeTenant('Clínica Beta');
    $otherUser = makeUser($other, 'beta@exemplo.com.br');
    $import = $this->service->start($other, $otherUser, portfolioCsv(['529.982.247-25;Maria Beta;;;;NF-1;10/09/2026;50,00;']), ImportMode::Incremental);
    $this->service->confirm($import);

    expect(Customer::count())->toBe(2)
        ->and(Customer::where('tenant_id', $this->tenant->id)->first()->name)->toBe('Maria')
        ->and(Bill::where('tenant_id', $other->id)->first()->amount_cents)->toBe(5000);
});

it('recusa uma segunda importação enquanto há uma em andamento', function () {
    runImport($this, ['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;'], confirm: false);

    $this->service->start($this->tenant, $this->user, portfolioCsv(['529.982.247-25;Maria;;;;NF-2;10/09/2026;100,00;']), ImportMode::Incremental);
})->throws(ImportRefused::class, 'há uma importação em andamento');

it('recusa o arquivo sem coluna obrigatória, sem conferir linha a linha', function () {
    $path = tempnam(sys_get_temp_dir(), 'csv');
    file_put_contents($path, "documento;nome;titulo;valor\n52998224725;Maria;NF-1;10,00\n");
    $import = $this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental);

    expect($import->status)->toBe(ImportStatus::Rejected)
        ->and($import->failure_reason)->toBe('coluna obrigatória ausente: vencimento');
});

it('descarta a conferência sem gravar nada', function () {
    $import = runImport($this, ['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;'], confirm: false);
    $this->service->discard($import);

    expect($import->refresh()->status)->toBe(ImportStatus::Discarded)
        ->and(Bill::count())->toBe(0)
        ->and(DB::table('import_rows')->where('import_id', $import->id)->count())->toBe(0);
});

function contractRoles(string $code): array
{
    $contract = Contract::where('code', $code)->firstOrFail()->load('customers');

    return $contract->customers->mapWithKeys(fn ($c) => [$c->document => Contract::rolesOf($c)])->all();
}

// R9, R9b: dois clientes no mesmo contrato; sem a coluna papel, cada um tem os dois papéis.
it('liga os dois clientes ao contrato, cada um com os dois papéis quando a coluna papel está vazia', function () {
    runImport($this, [
        '529.982.247-25;Ana;;;CT-1;NF-1;10/09/2026;100,00;',
        '390.533.447-05;Pedro;;;CT-1;NF-2;10/09/2026;100,00;',
    ]);

    expect(contractRoles('CT-1'))->toBe([
        '39053344705' => ['financial_responsible', 'holder'],
        '52998224725' => ['financial_responsible', 'holder'],
    ]);
});

// R9b: a coluna papel declara o papel do cliente da linha.
it('grava só o papel declarado na coluna papel', function () {
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    file_put_contents($path, "documento;nome;contrato;titulo;vencimento;valor;papel\n".
        "52998224725;Ana;CT-1;NF-1;10/09/2026;100,00;titular/responsável financeiro\n".
        "39053344705;Pedro;CT-1;NF-2;10/09/2026;100,00;titular\n");
    $import = $this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental);
    $this->service->confirm($import);

    expect(contractRoles('CT-1'))->toBe([
        '39053344705' => ['holder'],
        '52998224725' => ['financial_responsible', 'holder'],
    ]);
});

// R9b: papéis de linhas repetidas se somam, e carga posterior só acrescenta.
it('soma os papéis das linhas e das cargas seguintes, sem remover nenhum', function () {
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    $csv = fn (array $linhas) => "documento;nome;contrato;titulo;vencimento;valor;papel\n".implode("\n", $linhas)."\n";

    file_put_contents($path, $csv([
        '52998224725;Ana;CT-1;NF-1;10/09/2026;100,00;titular',
        '52998224725;Ana;CT-1;NF-2;10/09/2026;100,00;responsável financeiro',
    ]));
    $this->service->confirm($this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental));
    expect(contractRoles('CT-1'))->toBe(['52998224725' => ['financial_responsible', 'holder']]);

    file_put_contents($path, $csv(['52998224725;Ana;CT-1;NF-3;10/09/2026;100,00;titular']));
    $this->service->confirm($this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental));
    expect(contractRoles('CT-1'))->toBe(['52998224725' => ['financial_responsible', 'holder']]);
});

// Decisão do Paulo (23/10/2026): sem responsável financeiro declarado, os titulares respondem financeiramente.
it('trata os titulares como responsáveis financeiros quando ninguém é declarado, e só o declarado quando há', function () {
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    $csv = fn (array $linhas) => "documento;nome;contrato;titulo;vencimento;valor;papel\n".implode("\n", $linhas)."\n";

    file_put_contents($path, $csv([
        '52998224725;Ana;CT-1;NF-1;10/09/2026;100,00;titular',
        '39053344705;Pedro;CT-1;NF-2;10/09/2026;100,00;titular',
    ]));
    $this->service->confirm($this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental));

    $contract = Contract::where('code', 'CT-1')->first()->load('customers');
    expect($contract->financialResponsibles()->pluck('name')->sort()->values()->all())->toBe(['Ana', 'Pedro']);

    file_put_contents($path, $csv(['52998224725;Ana;CT-1;NF-3;10/09/2026;100,00;responsável financeiro']));
    $this->service->confirm($this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental));

    $contract = Contract::where('code', 'CT-1')->first()->load('customers');
    expect($contract->financialResponsibles()->pluck('name')->all())->toBe(['Ana']);
});

it('recusa a linha com papel inválido e mantém as demais', function () {
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    file_put_contents($path, "documento;nome;contrato;titulo;vencimento;valor;papel\n".
        "52998224725;Ana;CT-1;NF-1;10/09/2026;100,00;avalista\n".
        "39053344705;Pedro;CT-1;NF-2;10/09/2026;100,00;titular\n");
    $import = $this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental);

    expect($import->summary['valid'])->toBe(1)
        ->and($import->rejections()->first()->reason)->toBe('papel inválido: avalista')
        ->and($import->rejections()->first()->line)->toBe(2);
});

it('informa na conferência os contratos com mais de um cliente e as linhas com papel', function () {
    $path = tempnam(sys_get_temp_dir(), 'carteira');
    file_put_contents($path, "documento;nome;contrato;titulo;vencimento;valor;papel\n".
        "52998224725;Ana;CT-1;NF-1;10/09/2026;100,00;titular\n".
        "39053344705;Pedro;CT-1;NF-2;10/09/2026;100,00;\n".
        "11222333000181;Empresa;CT-2;NF-3;10/09/2026;100,00;\n");
    $import = $this->service->start($this->tenant, $this->user, $path, ImportMode::Incremental);

    expect($import->summary['contracts_multi_customer'])->toBe(1)->and($import->summary['roles_declared'])->toBe(1);
});
