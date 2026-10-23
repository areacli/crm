<?php

use App\Enums\UpcomingDisplay;
use App\Models\Bill;
use App\Models\Membership;
use App\Models\Profile;
use App\Portfolio\PortfolioQuery;
use Illuminate\Support\Carbon;

beforeEach(function () {
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->today = Carbon::create(2026, 10, 18);
});

function listFor($test, ?string $search = null, ?int $bracket = null)
{
    return (new PortfolioQuery($test->user, $test->today))->customers($search, $bracket)->get();
}

// R6 e R17: vencimento 10/09/2026, hoje 18/10/2026 -> 38 dias de atraso, faixa 31–60.
it('calcula o atraso e a faixa do cliente', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => ['2026-09-10', 100000]]);

    $row = listFor($this)->first();
    $query = new PortfolioQuery($this->user, $this->today);

    expect((int) $row->max_days_overdue)->toBe(38)
        ->and($query->bracketLabel($this->tenant, (int) $row->max_days_overdue))->toBe('31–60');
});

// R6: vence hoje e no futuro é "a vencer"; só o que venceu antes de hoje é vencido.
it('separa vencido de a vencer pela data de referência', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', [
        'NF-1' => ['2026-10-17', 10000],  // 1 dia de atraso
        'NF-2' => ['2026-10-18', 20000],  // vence hoje: a vencer
        'NF-3' => ['2026-12-10', 30000],  // a vencer
    ]);

    $row = listFor($this)->first();

    expect((int) $row->overdue_cents)->toBe(10000)->and((int) $row->upcoming_cents)->toBe(50000)
        ->and((int) $row->max_days_overdue)->toBe(1);
});

// Critério: título a vencer em 20/10 aparece como vencido, com 1 dia de atraso, em 21/10, sem nova importação.
it('um título a vencer passa a vencido com o passar dos dias, sem nova importação', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['NF-1' => ['2026-10-20', 10000]]);

    $before = (new PortfolioQuery($this->user, Carbon::create(2026, 10, 18)))->customers()->first();
    $after = (new PortfolioQuery($this->user, Carbon::create(2026, 10, 21)))->customers()->first();

    expect((int) $before->overdue_cents)->toBe(0)
        ->and((int) $after->overdue_cents)->toBe(10000)->and((int) $after->max_days_overdue)->toBe(1);
});

// R19: o cliente fica na faixa do título vencido mais atrasado (38 e 95 dias -> 91–180).
it('põe o cliente na faixa do título mais atrasado', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 1000], 'B' => ['2026-07-15', 1000]]);

    $row = listFor($this)->first();

    expect((int) $row->max_days_overdue)->toBe(95)
        ->and((new PortfolioQuery($this->user, $this->today))->bracketLabel($this->tenant, 95))->toBe('91–180');
});

it('só com títulos a vencer é "sem atraso"', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-12-10', 1000]]);

    $row = listFor($this)->first();

    expect($row->max_days_overdue)->toBeNull()
        ->and((new PortfolioQuery($this->user, $this->today))->bracketLabel($this->tenant, null))->toBe('sem atraso');
});

// R21: ordem padrão, maior valor vencido primeiro.
it('ordena pelo maior valor vencido', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Pequeno', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Grande', ['A' => ['2026-09-10', 9000]]);

    expect(listFor($this)->pluck('name')->all())->toBe(['Grande', 'Pequeno']);
});

// R21: busca por nome sem diferenciar maiúsculas nem acentos, e por documento.
it('busca por nome sem acento e por documento', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'João da Silva', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Maria Souza', ['A' => ['2026-09-10', 1000]]);

    expect(listFor($this, 'joao')->pluck('name')->all())->toBe(['João da Silva'])
        ->and(listFor($this, 'JOÃO')->pluck('name')->all())->toBe(['João da Silva'])
        ->and(listFor($this, '529.982')->pluck('name')->all())->toBe(['João da Silva']);
});

// R21 (revisão 3): com busca aparecem também os clientes sem título em cobrança; sem busca, não.
it('mostra o cliente sem título em cobrança só quando buscado', function () {
    $customer = makeCustomerWithBills($this->tenant, '52998224725', 'Maria Quitada', ['A' => ['2026-09-10', 1000]]);
    Bill::query()->update(['status' => 'withdrawn']);

    expect(listFor($this)->count())->toBe(0)
        ->and(listFor($this, 'quitada')->pluck('name')->all())->toBe(['Maria Quitada']);
});

// R20: no modo "só na ficha", quem só tem título a vencer fica fora da lista, mas a busca o acha.
it('no modo "só na ficha" esconde quem só tem título a vencer', function () {
    $this->tenant->settings->update(['upcoming_display' => UpcomingDisplay::DetailOnly]);
    makeCustomerWithBills($this->tenant, '52998224725', 'Só a vencer', ['A' => ['2026-12-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Com vencido', ['A' => ['2026-09-10', 1000]]);

    expect(listFor($this)->pluck('name')->all())->toBe(['Com vencido'])
        ->and(listFor($this, 'vencer')->pluck('name')->all())->toBe(['Só a vencer']);
});

it('filtra por faixa e por "sem atraso"', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Faixa 2', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Faixa 4', ['A' => ['2026-06-01', 1000]]);
    makeCustomerWithBills($this->tenant, '11222333000181', 'Sem atraso', ['A' => ['2026-12-10', 1000]]);

    expect(listFor($this, null, 1)->pluck('name')->all())->toBe(['Faixa 2'])
        ->and(listFor($this, null, 3)->pluck('name')->all())->toBe(['Faixa 4'])
        ->and(listFor($this, null, -1)->pluck('name')->all())->toBe(['Sem atraso']);
});

// MT-5: cada usuário só vê os credores em que tem a permissão de consultar.
it('só mostra os clientes dos credores em que o usuário pode consultar', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Da Alfa', ['A' => ['2026-09-10', 1000]]);
    $beta = makeTenant('Clínica Beta');
    makeCustomerWithBills($beta, '52998224725', 'Da Beta', ['A' => ['2026-09-10', 1000]]);

    expect(listFor($this)->pluck('name')->all())->toBe(['Da Alfa']);

    // O mesmo usuário passa a ter um vínculo também na Beta: a lista mistura os dois, sem seleção de credor (MT-4).
    Membership::factory()->create([
        'user_id' => $this->user->id, 'tenant_id' => $beta->id,
        'profile_id' => Profile::where('tenant_id', $beta->id)->first()->id,
    ]);
    $user = $this->user->fresh();

    expect((new PortfolioQuery($user, $this->today))->customers()->pluck('name')->sort()->values()->all())->toBe(['Da Alfa', 'Da Beta']);
});

// MT-7: cada credor tem as próprias faixas; o mesmo atraso cai em faixas diferentes.
it('usa as faixas de cada credor', function () {
    $beta = makeTenant('Clínica Beta');
    $beta->settings->update(['aging_brackets' => [['from' => 1, 'to' => 60], ['from' => 61, 'to' => null]]]);
    Membership::factory()->create([
        'user_id' => $this->user->id, 'tenant_id' => $beta->id,
        'profile_id' => Profile::where('tenant_id', $beta->id)->first()->id,
    ]);
    $user = $this->user->fresh();
    makeCustomerWithBills($this->tenant, '52998224725', 'Alfa', ['A' => ['2026-09-10', 1000]]);   // 38 dias
    makeCustomerWithBills($beta, '39053344705', 'Beta', ['A' => ['2026-09-10', 1000]]);

    $query = new PortfolioQuery($user, $this->today);

    expect($query->bracketLabel($this->tenant, 38))->toBe('31–60')
        ->and($query->bracketLabel($beta, 38))->toBe('1–60')
        ->and($query->customers(null, 0)->pluck('name')->all())->toBe(['Beta']);
});

it('um usuário sem permissão de consultar não vê nenhum cliente', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 1000]]);
    $profile = Profile::factory()->create(['tenant_id' => $this->tenant->id, 'name' => 'Sem consulta', 'permissions' => []]);
    $user = makeUser($this->tenant, 'semconsulta@exemplo.com.br');
    $user->memberships()->update(['profile_id' => $profile->id]);

    expect((new PortfolioQuery($user->fresh(), $this->today))->customers()->count())->toBe(0);
});
