<?php

use App\Access\AccessRefused;
use App\Enums\BillStatus;
use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Enums\ReversalMonthPolicy;
use App\Filament\Pages\ImportPayments;
use App\Filament\Pages\ImportReversals;
use App\Filament\Pages\PaymentSettings;
use App\Filament\Resources\PaymentChannels\Pages\CreatePaymentChannel;
use App\Filament\Resources\PaymentChannels\Pages\ListPaymentChannels;
use App\Filament\Resources\PaymentImports\Pages\ViewPaymentImport;
use App\Import\ImportService;
use App\Models\Bill;
use App\Models\Change;
use App\Models\Contract;
use App\Models\PaymentChannel;
use App\Models\Profile;
use App\Payments\CreditTransfer;
use App\Payments\PaymentColumns;
use App\Payments\PaymentRowValidator;
use App\Payments\ReversalRowValidator;
use App\Portfolio\PortfolioSummary;
use Illuminate\Auth\Access\AuthorizationException;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant('Alfa');
    $this->manager = makeUser($this->tenant);
    $this->channel = makeChannel($this->tenant);
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => [now()->subDays(40)->toDateString(), 100_000]], 'C-1');
});

it('recusa as telas de pagamentos a quem não tem a permissão, com registro (R33, R47)', function () {
    Profile::factory()->allowing([Permission::ViewPortfolio])->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador']);
    $operator = makeUser($this->tenant, 'op@exemplo.com.br', 'Operador');

    foreach (['/importar-pagamentos', '/importar-estornos', '/pagamentos', '/configuracao/canais', '/configuracao/pagamentos'] as $path) {
        $this->actingAs($operator)->get($path)->assertForbidden();
    }
    $this->assertDatabaseHas('access_events', ['event' => 'permission_denied', 'user_id' => $operator->id]);
    foreach (['/importar-pagamentos', '/importar-estornos', '/pagamentos', '/configuracao/canais', '/configuracao/pagamentos'] as $path) {
        $this->actingAs($this->manager)->get($path)->assertOk();
    }
});

it('cadastra canal, trava o código com pagamento e só apaga canal sem pagamento (R45)', function () {
    Livewire::actingAs($this->manager)->test(CreatePaymentChannel::class)
        ->fillForm(['type' => 'card', 'code' => '1029384756', 'description' => 'Cielo, loja virtual', 'active' => true])
        ->call('create')->assertHasNoFormErrors();
    $card = PaymentChannel::where('code', '1029384756')->first();
    expect($card->type->value)->toBe('card');
    $this->assertDatabaseHas('changes', ['subject_type' => 'channel', 'subject_id' => $card->id, 'event' => 'created']);

    // O mesmo código no mesmo credor é recusado.
    Livewire::actingAs($this->manager)->test(CreatePaymentChannel::class)
        ->fillForm(['type' => 'card', 'code' => '1029384756', 'description' => 'Outro', 'active' => true])
        ->call('create')->assertHasFormErrors(['code']);

    runPayments($this->tenant, $this->manager, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;400,00;pix']));
    expect(fn () => Gate::forUser($this->manager)->authorize('delete', $this->channel))->toThrow(AuthorizationException::class);
    expect(Gate::forUser($this->manager)->allows('delete', $card))->toBeTrue();
    Livewire::actingAs($this->manager)->test(ListPaymentChannels::class)->assertCanSeeTableRecords([$this->channel, $card]);
});

it('salva as políticas de pagamento com registro das mudanças (R46, R64, PD4)', function () {
    Livewire::actingAs($this->manager)->test(PaymentSettings::class)
        ->fillForm(['partial_payment_policy' => 'credit', 'withdrawn_payment_policy' => 'prevails', 'withdrawn_reversal_policy' => 'reopen', 'reversal_month_policy' => 'payment'])
        ->call('save');

    expect($this->tenant->settings->refresh()->reversal_month_policy)->toBe(ReversalMonthPolicy::Payment);
    expect(Change::where('event', 'partial_payment_policy_changed')->count())->toBe(1)
        ->and(Change::where('event', 'withdrawn_payment_policy_changed')->count())->toBe(0);
});

it('quem só envia não confirma, e quem confirma vê o botão (R34, R47)', function () {
    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::UploadPayments])->create(['tenant_id' => $this->tenant->id, 'name' => 'Financeiro']);
    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::ConfirmPayments])->create(['tenant_id' => $this->tenant->id, 'name' => 'Aprovador']);
    $sender = makeUser($this->tenant, 'fin@exemplo.com.br', 'Financeiro');
    $approver = makeUser($this->tenant, 'apr@exemplo.com.br', 'Aprovador');
    $import = runPayments($this->tenant, $sender, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;400,00;pix']), confirm: false);

    Livewire::actingAs($sender)->test(ViewPaymentImport::class, ['record' => $import->id])->assertActionHidden('confirm');
    Livewire::actingAs($approver)->test(ViewPaymentImport::class, ['record' => $import->id])->assertActionVisible('confirm')->callAction('confirm');
    expect(Bill::where('number', 'NF-1')->first()->paid_cents)->toBe(40_000);
});

it('oferece a planilha-modelo de pagamentos e de estornos e mostra as colunas', function () {
    Livewire::actingAs($this->manager)->test(ImportPayments::class)->assertSee('data_pagamento')->callAction('template')->assertFileDownloaded('planilha-modelo-pagamentos.csv');
    Livewire::actingAs($this->manager)->test(ImportReversals::class)->assertSee('identificador_estorno')->callAction('template')->assertFileDownloaded('planilha-modelo-estornos.csv');
    expect(array_column(PaymentColumns::for('payments'), 'name'))->toEqualCanonicalizing([...PaymentRowValidator::REQUIRED, ...PaymentRowValidator::OPTIONAL]);
    expect(array_column(PaymentColumns::for('reversals'), 'name'))->toEqualCanonicalizing([...ReversalRowValidator::REQUIRED, ...ReversalRowValidator::OPTIONAL]);
});

it('o resumo mostra o recuperado do mês por meio, o crédito e os pendentes; o estorno desconta no mês certo (R58, R64)', function () {
    runPayments($this->tenant, $this->manager, paymentsCsv([
        '341-1234-56789;P1;529.982.247-25;NF-1;'.now()->format('d/m/Y').';1.050,00;pix',
        '341-1234-56789;P2;529.982.247-25;NF-9;'.now()->format('d/m/Y').';100,00;boleto',
    ]));
    $summary = (new PortfolioSummary($this->manager))->forTenant($this->tenant);

    expect($summary['recovered'][0]['total'])->toBe(100_000)->and($summary['recovered'][0]['methods'])->toBe(['Pix' => 100_000])
        ->and($summary['credit_cents'])->toBe(5_000)->and($summary['pending_count'])->toBe(1)->and($summary['pending_cents'])->toBe(10_000);

    runPayments($this->tenant, $this->manager, reversalsCsv(['341-1234-56789;P1;E1;'.now()->format('d/m/Y').';350,00;']), 'reversals');
    $after = (new PortfolioSummary($this->manager))->forTenant($this->tenant);
    // R$ 50,00 saem do crédito e R$ 300,00 do título: o recuperado cai R$ 300,00 no mês do estorno.
    expect($after['recovered'][0]['total'])->toBe(70_000)->and($after['credit_cents'])->toBe(0);
});

it('a carga de carteira não atualiza nem retira título pago neste sistema (R57)', function () {
    runPayments($this->tenant, $this->manager, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.000,00;pix']));
    expect(Bill::where('number', 'NF-1')->first()->status)->toBe(BillStatus::Paid);

    $path = portfolioCsv(['529.982.247-25;Maria da Silva;;;C-1;NF-1;10/09/2026;2.000,00;', '390.533.447-05;João;;;C-2;NF-7;10/10/2026;500,00;']);
    $import = app(ImportService::class)->start($this->tenant, $this->manager, $path, ImportMode::FullSync);
    expect($import->summary['bills_paid_kept'])->toBe(1);
    app(ImportService::class)->confirm($import);

    $bill = Bill::where('number', 'NF-1')->first();
    expect($bill->status)->toBe(BillStatus::Paid)->and($bill->amount_cents)->toBe(100_000);
});

it('transfere crédito entre contratos do mesmo credor, com motivo, só com a permissão 17 (R55a)', function () {
    runPayments($this->tenant, $this->manager, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.300,00;pix']));
    $from = Bill::where('number', 'NF-1')->first()->contract;
    $to = Contract::factory()->create(['tenant_id' => $this->tenant->id, 'code' => 'C-9']);
    $service = app(CreditTransfer::class);

    expect($from->creditCents())->toBe(30_000);
    expect(fn () => $service->transfer($this->manager, $from, $to, 10_000, ' '))->toThrow(AccessRefused::class, 'motivo');
    expect(fn () => $service->transfer($this->manager, $from, $to, 40_000, 'acerto'))->toThrow(AccessRefused::class, 'maior que o crédito');
    $service->transfer($this->manager, $from, $to, 10_000, 'Pagamento feito no contrato errado');

    expect($from->creditCents())->toBe(20_000)->and($to->creditCents())->toBe(10_000);
    $this->assertDatabaseHas('changes', ['subject_type' => 'contract', 'subject_id' => $to->id, 'event' => 'credit_transferred']);

    $other = makeTenant('Beta');
    $foreign = Contract::factory()->create(['tenant_id' => $other->id, 'code' => 'B-1']);
    expect(fn () => $service->transfer($this->manager, $from, $foreign, 1_000, 'x'))->toThrow(AccessRefused::class, 'mesmo credor');

    Profile::factory()->allowing([Permission::ViewPortfolio])->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador']);
    $operator = makeUser($this->tenant, 'op@exemplo.com.br', 'Operador');
    expect(fn () => $service->transfer($operator, $from, $to, 1_000, 'x'))->toThrow(AccessRefused::class, 'permissão');
});
