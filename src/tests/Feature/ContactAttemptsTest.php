<?php

use App\Contacts\ContactAttemptService;
use App\Contacts\ContactRefused;
use App\Contacts\ContactResultManager;
use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Livewire\Contacts\Index as ContactsIndex;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Contract;
use App\Models\Customer;
use App\Models\Membership;
use App\Models\Profile;
use App\Portfolio\PortfolioSummary;
use App\Tenancy\InitialContactResults;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant('Alfa');
    InitialContactResults::createFor($this->tenant);
    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::RecordContactAttempts])->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador']);
    $this->manager = makeUser($this->tenant);
    $this->joana = makeUser($this->tenant, 'joana@exemplo.com.br', 'Operador');
    $this->maria = makeCustomerWithBills($this->tenant, '52998224725', 'Maria da Silva', ['NF-1' => [now()->subDays(30)->toDateString(), 100_000]], 'C-1');
    $this->service = app(ContactAttemptService::class);
});

function result(string $name): ContactResult
{
    return ContactResult::where('name', $name)->firstOrFail();
}

function attempt(array $extra = []): array
{
    return array_merge(['channel' => 'phone', 'result_id' => result('Não atendeu')->id], $extra);
}

it('registra o acionamento no cliente, com o momento e quem registrou (R69)', function () {
    $a = $this->service->record($this->joana, $this->maria, attempt(['contact_used' => '(11) 98765-4321']));

    expect($a->customer_id)->toBe($this->maria->id)->and($a->user_id)->toBe($this->joana->id)->and($a->result_type)->toBe(ContactResultType::NoContact)
        ->and($a->contact_used)->toBe('(11) 98765-4321')->and($a->contacted_at->diffInSeconds(now(), true))->toBeLessThan(5);
    $this->assertDatabaseHas('changes', ['subject_type' => 'contact_attempt', 'subject_id' => $a->id, 'event' => 'created', 'tenant_id' => $this->tenant->id]);
});

it('aplica a regra de retorno do resultado: exige, não permite, até 90 dias e depois do contato (R73)', function () {
    $needs = result('Pediu para retornar depois');
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => $needs->id])))->toThrow(ContactRefused::class, 'exige data de retorno');
    $ok = $this->service->record($this->joana, $this->maria, attempt(['result_id' => $needs->id, 'return_at' => now()->addDays(2)]));
    expect($ok->return_at)->not->toBeNull();

    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => result('Número ou endereço inexistente')->id, 'return_at' => now()->addDay()])))
        ->toThrow(ContactRefused::class, 'não permite data de retorno');
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => $needs->id, 'return_at' => now()->addDays(120)])))
        ->toThrow(ContactRefused::class, 'até 90 dias');
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => $needs->id, 'return_at' => now()->subHour()])))
        ->toThrow(ContactRefused::class, 'depois do contato');
});

it('aceita data do contato de até 7 dias atrás e recusa a de 10 dias e a futura (R70)', function () {
    $three = $this->service->record($this->joana, $this->maria, attempt(['contacted_at' => now()->subDays(3)]));
    expect($three->contacted_at->diffInDays(now(), true))->toBeGreaterThan(2.9)->and($three->created_at->diffInMinutes(now(), true))->toBeLessThan(1);
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['contacted_at' => now()->subDays(10)])))->toThrow(ContactRefused::class, 'até 7 dias atrás');
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['contacted_at' => now()->addDays(1)])))->toThrow(ContactRefused::class, 'futura');
});

it('guarda o texto como texto puro, sem caracteres de controle, e os limites de tamanho (R71, R72)', function () {
    $a = $this->service->record($this->joana, $this->maria, attempt(['text' => "<script>alert(1)</script>\nsegunda\x07 linha\u{200B}"]));
    expect($a->text)->toBe("<script>alert(1)</script>\nsegunda linha");

    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['text' => str_repeat('x', 2001)])))->toThrow(ContactRefused::class, '2000');
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['contact_used' => str_repeat('9', 61)])))->toThrow(ContactRefused::class, '60');
    $mail = $this->service->record($this->joana, $this->maria, attempt(['channel' => 'email', 'contact_used' => str_repeat('a', 240).'@x.com']));
    expect(mb_strlen($mail->contact_used))->toBe(246);
});

it('ignora o envio duplicado em até 10 segundos (exceção da R69)', function () {
    $when = now()->subHour();
    $first = $this->service->record($this->joana, $this->maria, attempt(['text' => 'igual', 'contacted_at' => $when]));
    $second = $this->service->record($this->joana, $this->maria, attempt(['text' => 'igual', 'contacted_at' => $when]));

    expect($second->id)->toBe($first->id)->and(ContactAttempt::count())->toBe(1);
});

it('recusa resultado desativado e resultado de outro credor (R66, R67)', function () {
    $caixa = result('Caixa postal');
    app(ContactResultManager::class)->setActive($this->manager, $caixa, false);
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => $caixa->id])))->toThrow(ContactRefused::class, 'Resultado desativado');

    $beta = makeTenant('Beta');
    InitialContactResults::createFor($beta);
    $foreign = ContactResult::where('tenant_id', $beta->id)->where('name', 'Não atendeu')->first();
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['result_id' => $foreign->id])))->toThrow(ContactRefused::class, 'Escolha o resultado');
});

it('o contrato é opcional, mas tem de ser do credor e ter o cliente (R69b)', function () {
    $contract = $this->maria->bills()->first()->contract;
    $a = $this->service->record($this->joana, $this->maria, attempt(['contract_id' => $contract->id]));
    expect($a->contract_id)->toBe($contract->id)->and($this->service->record($this->joana, $this->maria, attempt(['text' => 'sem contrato']))->contract_id)->toBeNull();

    $other = Contract::factory()->create(['tenant_id' => $this->tenant->id, 'code' => 'C-9']);
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['contract_id' => $other->id])))->toThrow(ContactRefused::class, 'não figura');
    $beta = makeTenant('Beta');
    $foreign = Contract::factory()->create(['tenant_id' => $beta->id, 'code' => 'B-1']);
    expect(fn () => $this->service->record($this->joana, $this->maria, attempt(['contract_id' => $foreign->id])))->toThrow(ContactRefused::class, 'não figura');
});

it('o acionamento é do cliente contatado, não dos outros clientes do contrato (R69a)', function () {
    $contract = $this->maria->bills()->first()->contract;
    $pedro = Customer::factory()->create(['tenant_id' => $this->tenant->id, 'document' => '39053344705', 'name' => 'Pedro']);
    $contract->customers()->attach($pedro->id, ['roles' => json_encode(['holder'])]);

    $a = $this->service->record($this->joana, $pedro, attempt(['contract_id' => $contract->id]));

    expect(ContactAttempt::where('customer_id', $pedro->id)->count())->toBe(1)->and(ContactAttempt::where('customer_id', $this->maria->id)->count())->toBe(0)
        ->and($a->contract_id)->toBe($contract->id);
});

it('exige as permissões 7 e 1 no credor do cliente, com a recusa registrada (R76, R33)', function () {
    Profile::factory()->allowing([Permission::ViewPortfolio])->create(['tenant_id' => $this->tenant->id, 'name' => 'Leitor']);
    $reader = makeUser($this->tenant, 'leitor@exemplo.com.br', 'Leitor');
    expect(fn () => $this->service->record($reader, $this->maria, attempt()))->toThrow(ContactRefused::class, 'permissão');
    $this->assertDatabaseHas('access_events', ['event' => 'permission_denied', 'user_id' => $reader->id, 'tenant_id' => $this->tenant->id]);

    // Marta registra na Alfa e só consulta a Beta.
    $beta = makeTenant('Beta');
    InitialContactResults::createFor($beta);
    $marta = makeUser($this->tenant, 'marta@exemplo.com.br', 'Operador');
    Profile::factory()->allowing([Permission::ViewPortfolio])->create(['tenant_id' => $beta->id, 'name' => 'Leitor']);
    Membership::factory()->create(['user_id' => $marta->id, 'tenant_id' => $beta->id, 'profile_id' => Profile::where('tenant_id', $beta->id)->where('name', 'Leitor')->first()->id]);
    $inBeta = makeCustomerWithBills($beta, '39053344705', 'Cliente da Beta', ['NF-1' => [now()->toDateString(), 1000]], 'B-1');
    expect(fn () => $this->service->record($marta, $inBeta, ['channel' => 'phone', 'result_id' => ContactResult::where('tenant_id', $beta->id)->first()->id]))->toThrow(ContactRefused::class);
    expect($this->service->record($marta, $this->maria, attempt())->tenant_id)->toBe($this->tenant->id);
});

it('anula com motivo, por quem registrou ou por quem tem a permissão 8, sem desfazer (R75)', function () {
    $a = $this->service->record($this->joana, $this->maria, attempt());
    expect(fn () => $this->service->void($this->joana, $a, '  '))->toThrow(ContactRefused::class, 'motivo');

    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::RecordContactAttempts])->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador 2']);
    $pedro = makeUser($this->tenant, 'pedro@exemplo.com.br', 'Operador 2');
    expect(fn () => $this->service->void($pedro, $a, 'engano'))->toThrow(ContactRefused::class, 'permissão');

    $this->service->void($this->manager, $a->fresh(), 'cliente errado');
    $a->refresh();
    expect($a->isVoided())->toBeTrue()->and($a->void_reason)->toBe('cliente errado')->and($a->voided_by)->toBe($this->manager->id);
    expect(fn () => $this->service->void($this->manager, $a, 'de novo'))->toThrow(ContactRefused::class, 'já foi anulado');

    $mine = $this->service->record($this->joana, $this->maria, attempt(['text' => 'outro']));
    $this->service->void($this->joana, $mine, 'registrei errado');
    expect($mine->fresh()->isVoided())->toBeTrue();
});

it('o gestor cria, renomeia, ordena e desativa resultados; o tipo não muda e nada se apaga (R66, R67)', function () {
    $manager = app(ContactResultManager::class);
    $new = $manager->create($this->manager, $this->tenant, 'Pediu boleto por e-mail', ContactResultType::SpokeWithCustomer, ReturnRule::Allowed);
    expect($new->position)->toBe(12)->and(ContactResult::where('tenant_id', $this->tenant->id)->count())->toBe(12);
    $this->assertDatabaseHas('changes', ['subject_type' => 'contact_result', 'subject_id' => $new->id, 'event' => 'created']);

    expect(fn () => $manager->create($this->manager, $this->tenant, 'não atendeu', ContactResultType::NoContact, ReturnRule::Allowed))->toThrow(ContactRefused::class, 'Já existe');
    $manager->update($this->manager, $new, 'Pediu boleto', ReturnRule::Required);
    expect($new->fresh()->name)->toBe('Pediu boleto')->and($new->fresh()->return_rule)->toBe(ReturnRule::Required)->and($new->fresh()->type)->toBe(ContactResultType::SpokeWithCustomer);

    $manager->move($this->manager, $new->fresh(), -1);
    expect($new->fresh()->position)->toBe(11);
    expect(fn () => $manager->create($this->joana, $this->tenant, 'Outro', ContactResultType::NoContact, ReturnRule::Allowed))->toThrow(ContactRefused::class, 'permissão');
    expect(Gate::forUser($this->manager)->allows('delete', $new))->toBeFalse();
});

it('a lista de resultados é de cada credor (R66)', function () {
    $beta = makeTenant('Beta');
    InitialContactResults::createFor($beta);
    app(ContactResultManager::class)->setActive($this->manager, result('Caixa postal'), false);

    expect(ContactResult::where('tenant_id', $this->tenant->id)->where('name', 'Caixa postal')->first()->active)->toBeFalse()
        ->and(ContactResult::where('tenant_id', $beta->id)->where('name', 'Caixa postal')->first()->active)->toBeTrue();
});

it('lista os acionamentos do período, com filtros, sem anulados e sem outro credor (R78, V10)', function () {
    $other = makeCustomerWithBills($this->tenant, '39053344705', 'Mário', ['NF-1' => [now()->toDateString(), 1000]], 'C-2');
    $this->service->record($this->joana, $this->maria, attempt(['text' => 'um']));
    $this->service->record($this->joana, $this->maria, attempt(['text' => 'dois', 'result_id' => result('Recado com terceiro')->id]));
    $this->service->record($this->manager, $other, attempt());
    $old = ContactAttempt::factory()->create(['customer_id' => $this->maria->id, 'result_id' => result('Não atendeu')->id, 'user_id' => $this->joana->id, 'contacted_at' => now()->subDays(10)]);
    $voided = $this->service->record($this->joana, $other, attempt(['text' => 'anulado']));
    $this->service->void($this->joana, $voided, 'engano');

    $beta = makeTenant('Beta');
    InitialContactResults::createFor($beta);
    $foreignCustomer = makeCustomerWithBills($beta, '11144477735', 'De outro credor', ['NF-1' => [now()->toDateString(), 1000]], 'B-1');
    ContactAttempt::factory()->create(['customer_id' => $foreignCustomer->id, 'result_id' => ContactResult::where('tenant_id', $beta->id)->first()->id]);

    $page = Livewire::actingAs($this->manager)->test(ContactsIndex::class);
    $count = fn () => $page->instance()->render()->getData()['rows']->total();
    expect($count())->toBe(3);                                                         // os 3 não anulados dos últimos 7 dias, só deste credor
    $page->set('operator', (string) $this->joana->id);
    expect($count())->toBe(2);
    $page->set('includeVoided', true);
    expect($count())->toBe(3);
});

it('o resumo conta acionamentos e clientes por tipo, sem anulados, um bloco por credor (R79)', function () {
    $mario = makeCustomerWithBills($this->tenant, '39053344705', 'Mário', ['NF-1' => [now()->toDateString(), 1000]], 'C-2');
    $this->service->record($this->joana, $this->maria, attempt());
    $this->service->record($this->joana, $this->maria, attempt(['text' => 'de novo']));
    $this->service->record($this->joana, $this->maria, attempt(['result_id' => result('Negociação em andamento')->id]));
    $this->service->record($this->joana, $mario, attempt(['result_id' => result('Recado com terceiro')->id]));
    $voided = $this->service->record($this->joana, $mario, attempt(['text' => 'x']));
    $this->service->void($this->joana, $voided, 'engano');
    ContactAttempt::factory()->create(['customer_id' => $mario->id, 'result_id' => result('Não atendeu')->id, 'contacted_at' => now()->subDays(20)]);

    $contacts = (new PortfolioSummary($this->manager))->forTenant($this->tenant)['contacts'];

    expect($contacts[7]['total'])->toBe(['attempts' => 4, 'customers' => 2])
        ->and($contacts[7]['types']['spoke_with_customer'])->toBe(['attempts' => 1, 'customers' => 1])
        ->and($contacts[7]['types']['spoke_with_third_party'])->toBe(['attempts' => 1, 'customers' => 1])
        ->and($contacts[7]['types']['no_contact'])->toBe(['attempts' => 2, 'customers' => 1])
        ->and($contacts[30]['total'])->toBe(['attempts' => 5, 'customers' => 2]);
});

it('a configuração é uma entrada com abas, e cada aba tem a própria permissão (P21)', function () {
    Profile::factory()->allowing([Permission::ViewPortfolio, Permission::ManageContactResults])->create(['tenant_id' => $this->tenant->id, 'name' => 'Resultados']);
    $onlyResults = makeUser($this->tenant, 'res@exemplo.com.br', 'Resultados');

    $this->actingAs($this->manager)->get('/configuracao')->assertRedirect('/configuracao/carteira');
    $this->actingAs($onlyResults)->get('/configuracao')->assertRedirect('/configuracao/acionamentos');
    $this->actingAs($onlyResults)->get('/configuracao/carteira')->assertForbidden();
    $this->actingAs($onlyResults)->get('/configuracao/acionamentos')->assertOk();
    $this->actingAs($this->joana)->get('/configuracao')->assertForbidden();

    // Nada de configuração solto no menu: canais, políticas e resultados são abas.
    $this->actingAs($this->manager)->get('/')->assertOk()->assertSee('Configuração')->assertDontSee('Canais de recebimento</span>', false);
});
