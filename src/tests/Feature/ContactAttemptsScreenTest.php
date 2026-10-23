<?php

use App\Enums\Permission;
use App\Livewire\Contacts\Index;
use App\Livewire\Customers\ContactAttempts as CustomerContactAttempts;
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
        ->call('openRecord')
        ->set('channel', 'phone')->set('resultId', (string) $naoAtendeu->id)->set('contactUsed', '(11) 98765-4321')->set('contactedAt', now()->format('Y-m-d\TH:i'))
        ->call('record')
        ->assertHasNoErrors()->assertDispatched('toast', message: 'Acionamento registrado')
        ->assertSee('Não atendeu')->assertSee('Telefone')->assertSee('(11) 98765-4321')->assertSee($this->joana->name);

    expect(ContactAttempt::count())->toBe(1);
});

it('o formulário não aparece para quem não registra, e a ficha mostra só o histórico (R76)', function () {
    ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->joana->id]);

    Livewire::actingAs($this->reader)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])
        ->assertDontSeeHtml('wire:click="openRecord"')->assertSee('1 registro')
        ->call('openRecord')->assertForbidden();
    Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertSeeHtml('wire:click="openRecord"');
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

    $component->assertSee('de 25 registros')->assertSee('Exibindo 1 a 20');
    $component->assertSee('contato 1')->assertDontSee('contato 25');
});

it('a anulação pede motivo, fica no histórico e some do botão (R75)', function () {
    $mine = ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->joana->id]);
    $others = ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'user_id' => $this->manager->id]);
    $component = Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id]);

    $component->assertSeeHtml('askVoid('.$mine->id.')')->assertDontSeeHtml('askVoid('.$others->id.')');
    Livewire::actingAs($this->joana)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->call('askVoid', $others->id)->assertForbidden();
    $component->call('askVoid', $mine->id)->call('void')->assertHasErrors(['voidReason' => 'required']);
    $component->call('askVoid', $mine->id)->set('voidReason', 'cliente errado')->call('void')->assertSee('Anulado: cliente errado');
    expect($mine->fresh()->isVoided())->toBeTrue();
    $component->assertDontSeeHtml('askVoid('.$mine->id.')');

    Livewire::actingAs($this->manager)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertSeeHtml('askVoid('.$others->id.')');
});

it('quem não vê o cliente não abre o histórico dele, nem pelo componente (MT-5, V10)', function () {
    $beta = makeTenant('Beta');
    $outsider = makeUser($beta, 'beta@exemplo.com.br');

    Livewire::actingAs($outsider)->test(CustomerContactAttempts::class, ['customerId' => $this->maria->id])->assertStatus(404);
});

it('a lista de acionamentos abre com 20 por página, com 20, 50 e 100 à escolha (P22)', function () {
    foreach (range(1, 25) as $i) {
        ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => ContactResult::first()->id, 'contacted_at' => now()->subMinutes($i)]);
    }

    $page = Livewire::actingAs($this->manager)->test(Index::class);
    expect($page->get('perPage'))->toBe(20);
    $page->assertSee('Exibindo 1 a 20 de 25 registros')->assertSeeHtml('<option value="50"')->assertSeeHtml('<option value="100"');
    $page->set('perPage', 50)->assertSee('Exibindo 1 a 25 de 25 registros');
    $page->set('perPage', 7)->assertSet('perPage', 20);
});
