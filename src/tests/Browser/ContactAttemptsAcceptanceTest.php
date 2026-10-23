<?php

use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Customer;
use Illuminate\Support\Facades\Artisan;

/*
| Critérios de aceite da especificação 04 em navegador real (V2): o operador registra um acionamento pela ficha e o vê no
| topo do histórico, e o gestor vê a lista, o resumo e os resultados na configuração.
*/
beforeEach(function () {
    Artisan::call('crm:demo-data', ['--customers' => 30]);
});

it('o operador registra um acionamento na ficha e o vê no histórico', function () {
    $page = visit('/login');
    $page->type('#form\\.email', 'operador@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-operador')->press('Login')
        ->assertSee('Resumo da carteira');
    $customer = Customer::query()->orderBy('id')->first();

    $page->navigate('/clientes/'.$customer->id)->assertSee('Acionamentos')->click('Registrar acionamento')
        ->select('.fi-modal-window select[id$="channel"]', 'phone')
        ->select('.fi-modal-window select[id$="result_id"]', (string) ContactResult::where('name', 'Não atendeu')->value('id'))
        ->type('.fi-modal-window textarea[id$="text"]', 'primeira tentativa')
        ->click('Enviar')->assertSee('Acionamento registrado');

    expect(ContactAttempt::where('customer_id', $customer->id)->where('text', 'primeira tentativa')->exists())->toBeTrue();
});

it('o gestor vê a lista, o resumo e os resultados dentro da configuração', function () {
    $page = visit('/login');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira')->assertSee('Últimos 7 dias');
    $page->navigate('/acionamentos')->assertSee('Acionamentos')->assertSee('Contato');
    $page->navigate('/configuracao')->assertPathIs('/configuracao/carteira')->assertSee('Políticas da carteira')->assertSee('Canais de recebimento')
        ->assertSee('Resultados de acionamento')->assertSee('Políticas de pagamento');
    $page->navigate('/configuracao/acionamentos')->assertSee('Pediu para retornar depois')->assertSee('Caixa postal');
});
