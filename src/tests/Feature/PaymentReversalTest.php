<?php

use App\Enums\BillStatus;
use App\Enums\WithdrawnReversalPolicy;
use App\Import\ImportService;
use App\Models\Bill;
use App\Models\Credit;
use App\Models\Payment;

beforeEach(function () {
    $this->tenant = makeTenant('Alfa');
    $this->user = makeUser($this->tenant);
    makeChannel($this->tenant);
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => [now()->subDays(40)->toDateString(), 100_000]], 'C-1');
});

function reversalBill(): Bill
{
    return Bill::where('number', 'NF-1')->firstOrFail()->refresh();
}

it('estorno parcial tira primeiro do crédito e depois do título, que volta à cobrança (R62)', function () {
    // Título de R$ 1.000,00 quitado por R$ 1.050,00: crédito de R$ 50,00.
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.050,00;pix']));
    expect(reversalBill()->status)->toBe(BillStatus::Paid);

    $import = runPayments($this->tenant, $this->user, reversalsCsv(['341-1234-56789;P1;E1;19/10/2026;300,00;contestação']), 'reversals', confirm: false);
    expect($import->summary['effect']['reopened'])->toBe(1)->and($import->summary['effect']['credit_reduced'])->toBe(1);
    app(ImportService::class)->confirm($import);

    // Crédito zera (R$ 50,00) e o título volta com saldo de R$ 250,00.
    expect(reversalBill()->status)->toBe(BillStatus::Active)->and(reversalBill()->balanceCents())->toBe(25_000)
        ->and(reversalBill()->contract->creditCents())->toBe(0)
        ->and(Payment::first()->reversed_cents)->toBe(30_000);
});

it('recusa pagamento inexistente, valor acima do estornável e data anterior ao pagamento (R61)', function () {
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;400,00;pix']));

    $import = runPayments($this->tenant, $this->user, reversalsCsv([
        '341-1234-56789;NADA;E1;19/10/2026;100,00;',
        '341-1234-56789;P1;E2;19/10/2026;100,00;',
        '341-1234-56789;P1;E3;19/10/2026;350,00;',
        '341-1234-56789;P1;E4;17/10/2026;50,00;',
    ]), 'reversals');

    expect($import->rejections()->orderBy('line')->pluck('reason')->all())->toBe([
        'pagamento não encontrado no canal', 'valor maior que o saldo estornável de R$ 300,00', 'data do estorno anterior ao pagamento',
    ]);
});

it('ignora o estorno já registrado (R61)', function () {
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;400,00;pix']));
    $csv = ['341-1234-56789;P1;E1;19/10/2026;100,00;'];
    runPayments($this->tenant, $this->user, reversalsCsv($csv), 'reversals');
    $again = runPayments($this->tenant, $this->user, reversalsCsv($csv), 'reversals', confirm: false);

    expect($again->summary['ignored'])->toBe(1)->and(reversalBill()->balanceCents())->toBe(70_000);
});

it('título retirado, quitado e estornado volta à cobrança ou a retirado, conforme a política (R62a)', function () {
    Bill::where('number', 'NF-1')->update(['status' => 'withdrawn', 'withdrawn_at' => now()]);
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P1;529.982.247-25;NF-1;18/10/2026;1.000,00;pix']));
    expect(reversalBill()->status)->toBe(BillStatus::Paid);
    $this->tenant->settings->update(['withdrawn_reversal_policy' => WithdrawnReversalPolicy::Withdrawn]);

    runPayments($this->tenant, $this->user, reversalsCsv(['341-1234-56789;P1;E1;19/10/2026;1.000,00;']), 'reversals');
    expect(reversalBill()->status)->toBe(BillStatus::Withdrawn)->and(reversalBill()->balanceCents())->toBe(100_000);
});

it('estorno de pagamento pendente cancela a pendência pelo valor estornado (R62)', function () {
    runPayments($this->tenant, $this->user, paymentsCsv(['341-1234-56789;P9;529.982.247-25;NF-9;18/10/2026;300,00;pix']));
    expect(Payment::first()->status)->toBe(Payment::PENDING);

    runPayments($this->tenant, $this->user, reversalsCsv(['341-1234-56789;P9;E1;19/10/2026;300,00;']), 'reversals');
    expect(Payment::first()->status)->toBe('cancelled')->and(Credit::count())->toBe(0);
});
