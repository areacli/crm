<?php

use App\Enums\Permission;
use App\Livewire\CustomerContactAttempts;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Profile;
use App\Tenancy\InitialContactResults;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant('Alfa');
    InitialContactResults::createFor($this->tenant);
    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::RecordContactAttempts])->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador']);
    Profile::factory()->allowing([Permission::ViewPortfolio])->create(['tenant_id' => $this->tenant->id, 'name' => 'Leitor']);
    $this->manager = makeUser($this->tenant);
    $this->joana = makeUser($this->tenant, 'joana@exemplo.com.br', 'Operador');
    $this->reader = makeUser($this->tenant, 'leitor@exemplo.com.br', 'Leitor');
    $this->maria = makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => [now()->subDays(30)->toDateString(), 100_000]], 'C-1');
    $this->maria->update(['phone' => '(11) 98765-4321']);
});

it('o operador registra pela ficha e o acionamento aparece no topo do histórico (R69, R74)', function () {
    $naoAtendeu = ContactResult::where('name', 'Não atendeu')->first();

    Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])
        ->callTableAction('record', data: ['channel' => 'phone', 'result_id' => $naoAtendeu->id, 'contact_used' => '(11) 98765-4321', 'contacted_at' => now()->toDateTimeString()])
        ->assertHasNoTableActionErrors()
        ->assertSee('Não atendeu')->assertSee('Telefone')->assertSee('(11) 98765-4321')->assertSee($this->joana->name);

    expect(ContactAttempt::count())->toBe(1);
});

it('o formulário não aparece para quem não registra, e a ficha mostra só o histórico (R76)', function () {
    ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->joana->id]);

    Livewire::actingAs($this->reader)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])
        ->assertTableActionHidden('record')->assertCountTableRecords(1);
    Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertTableActionVisible('record');
});

it('mostra o texto exatamente como digitado, sem interpretar (R72)', function () {
    ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'text' => "<script>alert(1)</script>\nsegunda linha"]);

    $html = Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->html();

    expect($html)->toContain('&lt;script&gt;alert(1)&lt;/script&gt;')->not->toContain('<script>alert(1)</script>');
});

it('mostra 20 por vez, do mais recente ao mais antigo (R74)', function () {
    foreach (range(1, 25) as $i) {
        ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'contacted_at' => now()->subHours($i), 'text' => "contato $i"]);
    }

    $component = Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id]);

    $component->assertCountTableRecords(25);
    expect($component->instance()->getTableRecords()->count())->toBe(20);
    $component->assertSee('contato 1')->assertDontSee('contato 25');
});

it('a anulação pede motivo, fica no histórico e some do botão (R75)', function () {
    $mine = ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->joana->id]);
    $others = ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->manager->id]);
    $component = Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id]);

    $component->assertTableActionVisible('void', $mine)->assertTableActionHidden('void', $others);
    $component->callTableAction('void', $mine, data: ['reason' => 'cliente errado'])->assertSee('Anulado: cliente errado');
    expect($mine->fresh()->isVoided())->toBeTrue();
    $component->assertTableActionHidden('void', $mine->fresh());

    Livewire::actingAs($this->manager)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertTableActionVisible('void', $others);
});

it('quem não vê o cliente não abre o histórico dele, nem pelo componente (MT-5, V10)', function () {
    $beta = makeTenant('Beta');
    $outsider = makeUser($beta, 'beta@exemplo.com.br');

    Livewire::actingAs($outsider)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertStatus(404);
});
