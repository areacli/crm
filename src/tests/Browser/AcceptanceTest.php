<?php

use App\Models\Import;
use Illuminate\Support\Facades\Artisan;

/*
| Critérios de aceite da especificação 01 em navegador real (V2): o usuário faz o que o critério descreve e
| confere o resultado na tela. Os testes de regra (Unit e Feature) cobrem os mesmos números por baixo.
*/

function signIn($page, string $email, string $password)
{
    return $page->type('#email', $email)->type('#password', $password)->click('button[type=submit]');
}

beforeEach(function () {
    Artisan::call('crm:demo-data', ['--customers' => 40]);
});

// R24: sem sessão, a tela de entrada; depois de entrar, volta para onde estava.
it('manda quem não tem sessão para a entrada e volta para a lista depois do login', function () {
    $page = visit('/clientes');

    $page->assertSee('Entrar');
    signIn($page, 'gestor@demo.exemplo.com.br', 'demonstracao-gestor')->assertPathIs('/clientes')->assertSee('Clientes');
});

// Mensagem igual para usuário inexistente e senha errada (R27).
it('recusa o login com a mesma mensagem para usuário inexistente e senha errada', function () {
    $a = visit('/login');
    signIn($a, 'ninguem@demo.exemplo.com.br', 'senha-errada-longa')->assertSee('Essas credenciais não correspondem');
    $b = visit('/login');
    signIn($b, 'gestor@demo.exemplo.com.br', 'senha-errada-longa')->assertSee('Essas credenciais não correspondem');
});

// Critério: o gestor abre a ficha e vê o contrato com os títulos, o atraso e a faixa.
it('mostra a lista, abre a ficha e mostra o contrato com os títulos', function () {
    $page = visit('/login');
    signIn($page, 'operador@demo.exemplo.com.br', 'demonstracao-operador')->assertPathIs('/');

    $page->navigate('/clientes')->assertSee('Clientes')->assertSee('Documento')->assertSee('Vencido')->assertSee('Faixa');
    $page->click('table tbody tr:first-child a')->assertSee('Contrato CT-')->assertSee('Maior atraso')->assertSee('Situação');
});

// Permissão 2 (enviar importação): o operador não vê "Importar carteira" no menu.
it('o operador não vê o menu de importação', function () {
    $page = visit('/login');

    signIn($page, 'operador@demo.exemplo.com.br', 'demonstracao-operador')->assertPathIs('/')->assertDontSee('Importar carteira');
});

// Critério: o gestor vê a conferência, com as linhas recusadas e o motivo, antes de qualquer gravação.
it('o gestor vê a conferência do batimento, com as recusadas e o que será retirado', function () {
    $page = visit('/login');
    signIn($page, 'gestor@demo.exemplo.com.br', 'demonstracao-gestor')->assertPathIs('/')->assertSee('Importar carteira');

    $page->navigate('/importacoes')->assertSee('Importações')->assertSee('batimento-outubro.csv');
    $id = Import::where('original_name', 'batimento-outubro.csv')->value('id');
    $page->navigate('/importacoes/'.$id)->assertSee('Conferência')->assertSee('Linhas recusadas')->assertSee('CPF inválido')
        ->assertSee('data inválida')->assertSee('Serão retirados')->assertSee('Confirmar importação');
});
