<?php

use App\Livewire\Customers\Index as ListCustomers;
use App\Livewire\Customers\Show as ViewCustomer;
use App\Models\Bill;
use App\Models\Contract;
use App\Models\Customer;
use App\Models\Membership;
use App\Models\Profile;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->actingAs($this->user);
});

it('lista os clientes com o documento mascarado', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => ['2026-09-10', 123456]]);

    Livewire::test(ListCustomers::class)
        ->assertSee('Maria da Silva')
        ->assertSee('529.***.***-25')
        ->assertDontSee('52998224725');
});

it('busca por nome sem acento na lista', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'João da Silva', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Maria Souza', ['A' => ['2026-09-10', 1000]]);

    Livewire::test(ListCustomers::class)
        ->set('search', 'joao')
        ->assertSee('João da Silva')
        ->assertDontSee('Maria Souza');
});

it('mostra a ficha com o contrato, os títulos e os retirados', function () {
    $customer = makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', [
        'NF-1' => ['2026-09-10', 100000], 'NF-2' => ['2026-12-10', 60000], 'NF-3' => ['2026-06-01', 5000],
    ], 'CT-2025-0042');
    Bill::where('number', 'NF-3')->update(['status' => 'withdrawn', 'withdrawn_at' => now()]);

    Livewire::test(ViewCustomer::class, ['customer' => $customer])
        ->assertSee('Maria da Silva')
        ->assertSee('529.982.247-25')
        ->assertSee('Contrato CT-2025-0042')
        ->assertSee('NF-1')
        ->assertSee('Retirados')
        ->assertSee('NF-3');
});

// MT-5: o link direto para um cliente de outro credor é recusado.
it('recusa abrir por link direto o cliente de um credor sem acesso', function () {
    $beta = makeTenant('Clínica Beta');
    $other = makeCustomerWithBills($beta, '52998224725', 'Da Beta', ['A' => ['2026-09-10', 1000]]);

    $this->get('/clientes/'.$other->id)->assertNotFound();
});

it('abre a lista pela raiz do painel depois do login', function () {
    $this->get('/clientes')->assertOk();
});

it('mostra na ficha os clientes do contrato com os papéis', function () {
    $ana = makeCustomerWithBills($this->tenant, '52998224725', 'Ana Souza', ['NF-1' => ['2026-09-10', 100000]], 'CT-7');
    $contract = Contract::where('code', 'CT-7')->first();
    $pedro = Customer::factory()->create(['tenant_id' => $this->tenant->id, 'document' => '39053344705', 'name' => 'Pedro Lima']);
    $contract->customers()->updateExistingPivot($ana->id, ['roles' => json_encode(['holder'])]);
    $contract->customers()->attach($pedro->id, ['roles' => json_encode(['holder'])]);

    Livewire::test(ViewCustomer::class, ['customer' => $ana])
        ->assertSee('Clientes do contrato')
        ->assertSee('Ana Souza')->assertSee('Pedro Lima')->assertSee('titular')
        ->assertSee('Sem responsável financeiro declarado: os titulares respondem financeiramente.');
});

it('não mostra o aviso quando há responsável financeiro declarado', function () {
    $ana = makeCustomerWithBills($this->tenant, '52998224725', 'Ana Souza', ['NF-1' => ['2026-09-10', 100000]], 'CT-7');
    Contract::where('code', 'CT-7')->first()->customers()->updateExistingPivot($ana->id, ['roles' => json_encode(['holder', 'financial_responsible'])]);

    Livewire::test(ViewCustomer::class, ['customer' => $ana])
        ->assertSee('responsável financeiro')
        ->assertDontSee('Sem responsável financeiro declarado');
});

// MTD2: filtro opcional de credor, só para quem vê mais de um.
it('filtra a lista por credor só quando o usuário vê mais de um', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Da Alfa', ['A' => ['2026-09-10', 1000]]);
    $beta = makeTenant('Clínica Beta');
    makeCustomerWithBills($beta, '39053344705', 'Da Beta', ['A' => ['2026-09-10', 1000]]);

    Livewire::test(ListCustomers::class)->assertDontSeeHtml('wire:model.live="tenant"');

    Membership::factory()->create(['user_id' => $this->user->id, 'tenant_id' => $beta->id, 'profile_id' => Profile::where('tenant_id', $beta->id)->first()->id]);
    $this->actingAs($this->user->fresh());

    Livewire::test(ListCustomers::class)
        ->assertSeeHtml('wire:model.live="tenant"')
        ->assertSee('Da Alfa')->assertSee('Da Beta')
        ->set('tenant', (string) $beta->id)
        ->assertSee('Da Beta')->assertDontSee('Da Alfa');
});

it('ordena a lista por nome ao clicar na coluna e inverte ao clicar de novo', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Zélia Prado', ['A' => ['2026-09-10', 1000]]);
    makeCustomerWithBills($this->tenant, '39053344705', 'Ana Souza', ['A' => ['2026-09-10', 1000]]);
    $first = fn ($html) => strpos($html, 'Ana Souza') < strpos($html, 'Zélia Prado');

    $component = Livewire::test(ListCustomers::class)->call('sortBy', 'name');
    expect($first($component->html()))->toBeTrue();
    expect($first($component->call('sortBy', 'name')->html()))->toBeFalse();
});
