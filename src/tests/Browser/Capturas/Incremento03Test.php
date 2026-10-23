<?php

use App\Models\Customer;
use App\Models\Import;
use Illuminate\Support\Facades\Artisan;

/*
| Capturas de tela do incremento 3. Só rodam quando pedidas: CAPTURAS=1 vendor/bin/pest tests/Browser/Capturas
| Os arquivos saem em tests/Browser/Screenshots e são copiados para a pasta de fotos do projeto.
*/
it('captura as telas do incremento 3', function () {
    Artisan::call('crm:demo-data', ['--customers' => 60]);
    $page = visit('/login');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira')->screenshot(filename: '01-resumo-com-recebimentos');

    $page->navigate('/canais')->assertSee('Canais de recebimento')->screenshot(filename: '02-canais');
    $page->navigate('/politicas-de-pagamento')->assertSee('Pagamento menor que o saldo')->screenshot(filename: '03-politicas-de-pagamento');
    $page->navigate('/importar-pagamentos')->assertSee('Colunas da planilha')->screenshot(filename: '04-importar-pagamentos');
    $page->navigate('/importar-estornos')->assertSee('identificador_estorno')->screenshot(filename: '05-importar-estornos');
    $page->navigate('/pagamentos')->assertSee('pagamentos-outubro.csv')->screenshot(filename: '06-pagamentos-lista');
    $id = Import::where('kind', 'payments')->value('id');
    $page->navigate('/pagamentos/'.$id)->assertSee('Resultado')->screenshot(filename: '07-pagamentos-resultado');

    $customer = Customer::query()->whereHas('bills', fn ($q) => $q->where('status', 'paid'))->orderBy('id')->first();
    $page->navigate('/clientes/'.$customer->id)->assertSee('Pagos')->screenshot(filename: '08-ficha-com-pagos');
})->skip(fn () => ! getenv('CAPTURAS'), 'só roda com CAPTURAS=1');
