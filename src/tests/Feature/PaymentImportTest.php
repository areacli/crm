<?php

use App\Enums\BillStatus;
use App\Enums\PartialPaymentPolicy;
use App\Enums\WithdrawnPaymentPolicy;
use App\Import\ImportService;
use App\Models\Bill;
use App\Models\Credit;
use App\Models\Payment;

beforeEach(function () {
    $this->tenant = makeTenant('Alfa');
    $this->user = makeUser($this->tenant);
    $this->channel = makeChannel($this->tenant);
    $this->customer = makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', [
        'NF-1' => [now()->subDays(40)->toDateString(), 100_000],
        'NF-2' => [now()->subDays(10)->toDateString(), 100_000],
    ], 'C-1');
});

function bill(string $number): Bill
{
    return Bill::where('number', $number)->firstOrFail()->refresh();
}

it('confere sem gravar e, ao confirmar, quita o título, que sai da cobrança (R50, R54)', function () {
    $import = runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;PIX1;529.982.247-25;NF-1;18/10/2026;1.000,00;pix']), confirm: false);

    expect($import->summary['effect']['settled'])->toBe(1)->and($import->summary['effect']['applied_cents'])->toBe(100_000);
    expect(Payment::count())->toBe(0)->and(bill('NF-1')->status)->toBe(BillStatus::Active);

    app(ImportService::class)->confirm($import);
    expect(bill('NF-1')->status)->toBe(BillStatus::Paid)->and(bill('NF-1')->paid_cents)->toBe(100_000)
        ->and(Payment::first()->applied_cents)->toBe(100_000);
});

it('enviar o mesmo arquivo de novo não muda nada (R48)', function () {
    $csv = ['341-1234-56789;PIX1;529.982.247-25;NF-1;18/10/2026;400,00;pix'];
    runPayments($this->tenant, $this->user, paymentsCsv($csv));
    $second = runPayments($this->tenant, $this->user, paymentsCsv($csv), confirm: false);

    expect($second->summary['ignored'])->toBe(1)->and($second->summary['valid'])->toBe(0);
    app(ImportService::class)->discard($second);
    runPayments($this->tenant, $this->user, paymentsCsv($csv));
    expect(Payment::count())->toBe(1)->and(bill('NF-1')->paid_cents)->toBe(40_000);
});

it('recusa o repetido no arquivo e aceita o mesmo identificador em dois canais (R48)', function () {
    makeChannel($this->tenant, '999');
    $import = runPayments($this->tenant, $this->user, paymentsCsv([
        '341-1234-56789;A;529.982.247-25;NF-1;18/10/2026;100,00;pix',
        '341-1234-56789;A;529.982.247-25;NF-1;18/10/2026;100,00;pix',
        '999;A;529.982.247-25;NF-2;18/10/2026;100,00;pix',
    ]));

    expect($import->rejections()->pluck('reason')->all())->toBe(['pagamento repetido na linha 2'])
        ->and(Payment::count())->toBe(2);
});

it('baixa parcial ou crédito sem baixar, conforme a política do credor (R46)', function () {
    $this->tenant->settings->update(['partial_payment_policy' => PartialPaymentPolicy::Partial]);
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;400,00;pix']));
    expect(bill('NF-1')->balanceCents())->toBe(60_000)->and(bill('NF-1')->status)->toBe(BillStatus::Active);

    $this->tenant->settings->update(['partial_payment_policy' => PartialPaymentPolicy::Credit]);
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P2;529.982.247-25;NF-2;18/10/2026;400,00;pix']));
    expect(bill('NF-2')->balanceCents())->toBe(100_000)
        ->and((int) Credit::where('reason', 'without_settling')->sum('amount_cents'))->toBe(40_000);
});

it('o excedente vira crédito do contrato do título, e título já pago também (R50, R50a, R51)', function () {
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.050,00;pix']));
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P2;529.982.247-25;NF-1;19/10/2026;200,00;pix']));

    $contract = bill('NF-1')->contract;
    expect($contract->creditCents())->toBe(25_000)
        ->and(Credit::pluck('reason')->sort()->values()->all())->toBe(['already_paid', 'excess']);
});

it('recusa a linha sem título e a de canal não cadastrado ou desativado (R49, R52a)', function () {
    makeChannel($this->tenant, 'OFF', active: false);
    $import = runPayments($this->tenant, $this->user, paymentsCsv([
        '341-1234-56789;S1;529.982.247-25;;18/10/2026;100,00;pix',
        '341-1234-5678;S2;529.982.247-25;NF-1;18/10/2026;100,00;pix',
        'OFF;S3;529.982.247-25;NF-1;18/10/2026;100,00;pix',
        '341-1234-56789;S4;529.982.247-25;NF-1;18/10/2099;100,00;pix',
        '341-1234-56789;S5;529.982.247-25;NF-1;18/10/2026;100,00;cheque',
    ]));

    expect($import->rejections()->orderBy('line')->pluck('reason')->all())->toBe([
        'título não informado', 'canal não cadastrado ou desativado', 'canal não cadastrado ou desativado',
        'data de pagamento futura', 'meio de pagamento fora da lista',
    ])->and(Payment::count())->toBe(0);
});

it('título fora da carteira fica pendente, sem crédito, e é reavaliado quando aparece (R52, R52a)', function () {
    $import = runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-9;18/10/2026;300,00;pix']));
    expect($import->summary['effect']['pending_new'])->toBe(1)->and(Payment::first()->status)->toBe(Payment::PENDING)
        ->and(Credit::count())->toBe(0);

    // A carteira passa a ter o título: a próxima conferência de pagamentos reapresenta o pendente.
    $existing = bill('NF-1');
    Bill::factory()->create(['contract_id' => $existing->contract_id, 'tenant_id' => $this->tenant->id, 'customer_id' => $existing->customer_id, 'number' => 'NF-9', 'due_date' => now()->subDays(5)->toDateString(), 'amount_cents' => 30_000]);
    $next = runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P2;529.982.247-25;NF-2;18/10/2026;100,00;pix']));

    expect($next->summary['effect']['pending_applied'])->toBe(1)
        ->and(Payment::where('identifier', 'P1')->first()->status)->toBe(Payment::APPLIED)
        ->and(bill('NF-9')->status)->toBe(BillStatus::Paid);
});

it('aplica vários pagamentos do mesmo título em ordem de data (R53)', function () {
    runPayments($this->tenant, $this->user, paymentsCsv([
        '341-1234-56789;P2;529.982.247-25;NF-1;19/10/2026;300,00;pix',
        '341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;800,00;pix',
    ]));

    // O primeiro (18/10) deixa saldo de R$ 200,00; o segundo quita e gera crédito de R$ 100,00.
    expect(bill('NF-1')->status)->toBe(BillStatus::Paid)->and(bill('NF-1')->contract->creditCents())->toBe(10_000);
});

it('título retirado: o pagamento prevalece ou vira crédito, conforme a política (R46a)', function () {
    Bill::where('number', 'NF-1')->update(['status' => 'withdrawn', 'withdrawn_at' => now()]);
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.000,00;pix']));
    expect(bill('NF-1')->status)->toBe(BillStatus::Paid);

    Bill::where('number', 'NF-2')->update(['status' => 'withdrawn', 'withdrawn_at' => now()]);
    $this->tenant->settings->update(['withdrawn_payment_policy' => WithdrawnPaymentPolicy::Credit]);
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P2;529.982.247-25;NF-2;18/10/2026;1.000,00;pix']));
    expect(bill('NF-2')->status)->toBe(BillStatus::Withdrawn)->and((int) Credit::where('reason', 'withdrawn')->sum('amount_cents'))->toBe(100_000);
});

it('não toca nos títulos de outro credor (V10)', function () {
    $beta = makeTenant('Beta');
    makeChannel($beta, '341-1234-56789');
    makeCustomerWithBills($beta, '52998224725', 'Maria Beta', ['NF-1' => [now()->subDays(40)->toDateString(), 50_000]], 'B-1');

    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;500,00;pix']));

    expect(Bill::where('tenant_id', $beta->id)->first()->status)->toBe(BillStatus::Active);
});
