<?php

use App\Models\Customer;
use Illuminate\Support\Facades\Artisan;

/*
| Capturas de tela do incremento 4. Só rodam quando pedidas: CAPTURAS=1 vendor/bin/pest tests/Browser/Capturas
| Os arquivos saem em tests/Browser/Screenshots e são copiados para a pasta de fotos do projeto.
*/
it('captura as telas do incremento 4', function () {
    Artisan::call('crm:demo-data', ['--customers' => 60]);
    $page = visit('/login');
    $page->type('#email', 'gestor@demo.exemplo.com.br')->type('#password', 'demonstracao-gestor')->click('button[type=submit]')
        ->assertSee('Resumo da carteira')->screenshot(filename: '01-resumo-com-acionamentos');
    $page->navigate('/acionamentos')->assertSee('Acionamentos')->screenshot(filename: '02-lista-de-acionamentos');

    $customer = Customer::query()->whereHas('bills')->orderBy('id')->first();
    $page->navigate('/clientes/'.$customer->id)->assertSee('Acionamentos')->screenshot(filename: '03-ficha-com-acionamentos');
    $page->click('Registrar acionamento')->assertSee('Canal')->screenshot(filename: '04-registrar-acionamento');
    $page->navigate('/configuracao/acionamentos')->assertSee('Resultados de acionamento')->screenshot(filename: '05-resultados-na-configuracao');
    $page->navigate('/configuracao/carteira')->assertSee('Políticas da carteira')->screenshot(filename: '06-configuracao-com-abas');
})->skip(fn () => ! getenv('CAPTURAS'), 'só roda com CAPTURAS=1');
