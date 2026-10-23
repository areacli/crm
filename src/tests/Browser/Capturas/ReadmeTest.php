<?php

use App\Models\Customer;
use App\Models\Import;
use App\Models\Profile;
use Illuminate\Support\Facades\Artisan;

/*
| Fotos do README: as telas da versão atual, com os dados fictícios de demonstração. Só rodam quando pedidas:
| CAPTURAS=1 vendor/bin/pest tests/Browser/Capturas/ReadmeTest.php (saem em tests/Browser/Screenshots; vão para docs/telas).
*/
it('captura as telas do README', function () {
    Artisan::call('crm:demo-data', ['--customers' => 80]);
    $page = visit('/login');
    $page->assertSee('Faça login')->screenshot(filename: 'readme-entrada');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira')->screenshot(filename: 'readme-resumo');
    $page->navigate('/clientes')->assertSee('Clientes')->screenshot(filename: 'readme-clientes');

    $customer = Customer::query()->whereHas('bills', fn ($q) => $q->where('status', 'paid'))->whereHas('bills.contract.credits')->orderBy('id')->first()
        ?? Customer::query()->whereHas('bills', fn ($q) => $q->where('status', 'paid'))->orderBy('id')->first();
    $page->navigate('/clientes/'.$customer->id)->assertSee('Pagos')->screenshot(filename: 'readme-ficha-do-cliente');

    $batimento = Import::where('original_name', 'batimento-outubro.csv')->value('id');
    $page->navigate('/importacoes/'.$batimento)->assertSee('Linhas recusadas')->screenshot(filename: 'readme-conferencia-da-carteira');
    $payments = Import::where('kind', 'payments')->value('id');
    $page->navigate('/pagamentos/'.$payments)->assertSee('Resultado')->screenshot(filename: 'readme-pagamentos');
    $page->navigate('/configuracao/canais')->assertSee('Canais de recebimento')->screenshot(filename: 'readme-canais');
    $page->navigate('/usuarios')->assertSee('Usuários')->screenshot(filename: 'readme-usuarios');
    $page->navigate('/perfis/'.Profile::where('name', 'Operador')->value('id').'/editar')->assertSee('Permissões')->screenshot(filename: 'readme-perfil');
})->skip(fn () => ! getenv('CAPTURAS'), 'só roda com CAPTURAS=1');
