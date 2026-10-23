<?php

use App\Models\Customer;
use App\Models\Import;
use Illuminate\Support\Facades\Artisan;

/*
| Capturas de tela do incremento 1, para o diário e, depois, o blog (pedido do Paulo, M18 da decisão 0013).
| Só rodam quando pedidas: CAPTURAS=1 vendor/bin/pest tests/Browser/Capturas
| Os arquivos saem em tests/Browser/Screenshots e são copiados para a pasta de fotos do projeto.
*/
it('captura as telas do incremento 1', function () {
    Artisan::call('crm:demo-data', ['--customers' => 80]);
    // Valores variados na carteira de demonstração: dá faixas diferentes no resumo.
    $page = visit('/login');
    $page->assertSee('Entrar')->screenshot(filename: '01-entrada');

    $page->type('#email', 'gestor@demo.exemplo.com.br')->type('#password', 'demonstracao-gestor')->click('button[type=submit]')
        ->assertSee('Resumo da carteira')->screenshot(filename: '02-resumo');

    $page->navigate('/clientes')->assertSee('Clientes')->screenshot(filename: '03-clientes-lista');

    $page->navigate('/importar')->assertSee('Importar carteira')->screenshot(filename: '04-importar-carteira');

    $page->navigate('/importacoes')->assertSee('batimento-outubro.csv')->screenshot(filename: '05-importacoes-lista');

    $id = Import::where('original_name', 'batimento-outubro.csv')->value('id');
    $page->navigate('/importacoes/'.$id)->assertSee('Linhas recusadas')->screenshot(filename: '06-importacao-conferida');

    $page->navigate('/configuracao/carteira')->assertSee('Políticas da carteira')->screenshot(filename: '07-configuracao');

    $customer = Customer::orderBy('id')->first();
    $page->navigate('/clientes/'.$customer->id)->assertSee('Maior atraso')->screenshot(filename: '08-ficha-do-cliente');
})->skip(fn () => ! getenv('CAPTURAS'), 'só roda com CAPTURAS=1');
