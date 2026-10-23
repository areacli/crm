<?php

use App\Enums\UpcomingDisplay;
use App\Filament\Pages\Summary;
use App\Models\Bill;
use App\Models\Membership;
use App\Models\Profile;
use App\Portfolio\PortfolioSummary;
use Illuminate\Support\Carbon;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->today = Carbon::create(2026, 10, 18);
});

function summaryOf($test)
{
    return (new PortfolioSummary($test->user, $test->today))->forTenant($test->tenant);
}

// R23: cliente com títulos de 5 e 400 dias. Por cliente, os dois valores vão para "mais de 360"; por título, um vai para 1–30 e o outro para "mais de 360".
it('distribui por cliente e por título, como no exemplo da especificação', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', [
        'A' => [$this->today->copy()->subDays(5)->toDateString(), 10000],
        'B' => [$this->today->copy()->subDays(400)->toDateString(), 90000],
    ]);

    $s = summaryOf($this);
    $byCustomer = collect($s['by_customer'])->keyBy('label');
    $byBill = collect($s['by_bill'])->keyBy('label');

    expect($byCustomer['mais de 360']['count'])->toBe(1)->and($byCustomer['mais de 360']['cents'])->toBe(100000)
        ->and($byCustomer['1–30']['count'])->toBe(0)
        ->and($byBill['1–30']['cents'])->toBe(10000)->and($byBill['mais de 360']['cents'])->toBe(90000);
});

it('soma vencido e a vencer e conta clientes e títulos', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 100000], 'B' => ['2026-12-10', 60000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'João', ['A' => ['2026-12-10', 5000]]);

    $s = summaryOf($this);

    expect($s['customers'])->toBe(2)->and($s['customers_overdue'])->toBe(1)->and($s['bills'])->toBe(3)
        ->and($s['overdue_cents'])->toBe(100000)->and($s['upcoming_cents'])->toBe(65000);
});

it('ignora títulos retirados', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 100000]]);
    Bill::query()->update(['status' => 'withdrawn']);

    expect(summaryOf($this)['bills'])->toBe(0)->and(summaryOf($this)['overdue_cents'])->toBe(0);
});

// MT-20: um resumo por credor, com as faixas de cada um.
it('faz um resumo por credor, cada um com as próprias faixas', function () {
    $beta = makeTenant('Clínica Beta');
    $beta->settings->update(['aging_brackets' => [['from' => 1, 'to' => 60], ['from' => 61, 'to' => null]]]);
    Membership::factory()->create(['user_id' => $this->user->id, 'tenant_id' => $beta->id, 'profile_id' => Profile::where('tenant_id', $beta->id)->first()->id]);
    makeCustomerWithBills($this->tenant, '52998224725', 'Da Alfa', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($beta, '39053344705', 'Da Beta', ['A' => ['2026-09-10', 2000]]);

    $summaries = (new PortfolioSummary($this->user->fresh(), $this->today))->perTenant();

    expect($summaries)->toHaveCount(2)
        ->and($summaries[0]['tenant']->name)->toBe('Clínica Beta')
        ->and($summaries[0]['labels'])->toBe(['1–60', 'mais de 60'])
        ->and($summaries[1]['labels'])->toHaveCount(6);
});

it('mostra o resumo na entrada do sistema', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 123456]]);
    $this->actingAs($this->user);

    Livewire::test(Summary::class)
        ->assertSee('Resumo da carteira')
        ->assertSee('Por cliente')->assertSee('Por título')
        ->assertSee('1.234,56');
});

// R20 "somado": o total em cobrança soma o a vencer, com o vencido à parte.
it('no modo somado mostra o total em cobrança e o vencido à parte', function () {
    $this->tenant->settings->update(['upcoming_display' => UpcomingDisplay::Summed]);
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 80000], 'B' => ['2026-12-10', 120000]]);
    $this->actingAs($this->user);

    Livewire::test(Summary::class)->assertSee('Em cobrança, somando o a vencer: R$ 2.000,00 (vencido R$ 800,00).');
});

it('a entrada leva ao resumo para quem tem sessão', function () {
    $this->actingAs($this->user)->get('/')->assertOk()->assertSee('Resumo da carteira');
});
