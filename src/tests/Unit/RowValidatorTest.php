<?php

use App\Import\RowValidator;

function validRow(array $override = []): array
{
    return array_merge([
        '__extra' => '', '__short' => '',
        'documento' => '529.982.247-25', 'nome' => 'Maria da Silva', 'telefone' => '(11) 98765-4321',
        'email' => 'maria@exemplo.com.br', 'contrato' => 'CT-2025-0042', 'titulo' => 'NF-1024/3',
        'vencimento' => '10/09/2026', 'valor' => '1.234,56', 'descricao' => 'Mensalidade setembro',
    ], $override);
}

it('aceita uma linha válida e normaliza os campos', function () {
    [$row, $reason] = (new RowValidator)->validate(2, validRow());

    expect($reason)->toBeNull()
        ->and($row->document)->toBe('52998224725')
        ->and($row->amountCents)->toBe(123456)
        ->and($row->dueDate)->toBe('2026-09-10')
        ->and($row->contract)->toBe('CT-2025-0042');
});

it('trata contrato, telefone, e-mail e descrição vazios como ausentes', function () {
    [$row] = (new RowValidator)->validate(2, validRow(['contrato' => '', 'telefone' => '', 'email' => '', 'descricao' => '']));

    expect($row->contract)->toBeNull()->and($row->phone)->toBeNull()->and($row->email)->toBeNull()->and($row->description)->toBeNull();
});

it('recusa a linha com o motivo', function (array $override, string $reason) {
    expect((new RowValidator)->validate(7, validRow($override)))->toBe([null, $reason]);
})->with([
    'CPF inválido' => [['documento' => '111.111.111-11'], 'CPF inválido'],
    'data inválida' => [['vencimento' => '31/02/2026'], 'data inválida'],
    'valor zero' => [['valor' => '0,00'], 'valor deve ser maior que zero'],
    'valor com três casas' => [['valor' => '12,345'], 'valor com mais de duas casas decimais'],
    'nome vazio' => [['nome' => ''], 'nome obrigatório'],
    'título vazio' => [['titulo' => ''], 'título obrigatório'],
    'células a mais' => [['__extra' => '1'], 'linha com mais colunas que o cabeçalho'],
    'colunas a menos' => [['__short' => '1'], 'linha incompleta'],
    'nome longo' => [['nome' => str_repeat('a', 301)], 'nome acima de 300 caracteres'],
    'título longo' => [['titulo' => str_repeat('a', 101)], 'título acima de 100 caracteres'],
    'e-mail longo' => [['email' => str_repeat('a', 255)], 'e-mail acima de 254 caracteres'],
]);

// R9b: coluna papel, tolerante a maiúsculas e acentos; vazio não declara; desconhecido recusa a linha.
it('lê o papel declarado, sem diferenciar maiúsculas nem acentos', function (string $raw, ?string $roles) {
    [$row, $reason] = (new RowValidator)->validate(2, validRow(['papel' => $raw]));

    expect($reason)->toBeNull()->and($row->roles)->toBe($roles);
})->with([
    'vazio' => ['', null],
    'titular' => ['titular', 'holder'],
    'maiúscula' => ['TITULAR', 'holder'],
    'responsável com acento' => ['Responsável Financeiro', 'financial_responsible'],
    'sem acento' => ['responsavel financeiro', 'financial_responsible'],
    'os dois' => ['titular/responsável financeiro', 'financial_responsible,holder'],
    'os dois, com espaço' => ['responsavel financeiro / titular', 'financial_responsible,holder'],
]);

it('recusa a linha com papel desconhecido', function () {
    expect((new RowValidator)->validate(9, validRow(['papel' => 'avalista'])))->toBe([null, 'papel inválido: avalista'])
        ->and((new RowValidator)->validate(9, validRow(['papel' => 'titular/avalista'])))->toBe([null, 'papel inválido: avalista']);
});
