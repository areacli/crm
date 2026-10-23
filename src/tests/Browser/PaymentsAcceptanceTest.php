<?php

use Illuminate\Support\Facades\Artisan;

/*
| Critérios de aceite da especificação 03 em navegador real (V2): o financeiro vê os recebimentos no resumo, a lista de
| pagamentos com a conferência e o crédito do contrato na ficha do cliente.
*/
beforeEach(function () {
    Artisan::call('crm:demo-data', ['--customers' => 40]);
});

it('mostra o recuperado no resumo e a lista de pagamentos importados', function () {
    $page = visit('/login');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira')->assertSee('Recuperado em')->assertSee('Créditos dos contratos')->assertSee('Pagamentos pendentes');

    $page->navigate('/pagamentos')->assertSee('pagamentos-outubro.csv')->assertSee('estornos-outubro.csv');
    $page->navigate('/configuracao/canais')->assertSee('341-1234-56789')->assertSee('Cielo, loja virtual');
    $page->navigate('/importar-pagamentos')->assertSee('data_pagamento')->assertSee('Baixar a planilha-modelo');
});
