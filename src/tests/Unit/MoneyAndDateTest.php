<?php

use App\Support\BrDate;
use App\Support\Money;

// R5: valor em centavos, maior que zero, no máximo duas casas.
it('converte valores brasileiros em centavos', function (string $raw, int $cents) {
    expect(Money::parseCents($raw))->toBe([$cents, null]);
})->with([
    ['1.234,56', 123456],
    ['1234,56', 123456],
    ['100', 10000],
    ['0,5', 50],
    ['12,30', 1230],
]);

it('recusa valor zero, com três casas ou mal formado', function (string $raw, string $reason) {
    expect(Money::parseCents($raw))->toBe([null, $reason]);
})->with([
    ['0,00', 'valor deve ser maior que zero'],
    ['12,345', 'valor com mais de duas casas decimais'],
    ['abc', 'valor inválido'],
    ['', 'valor obrigatório'],
]);

it('formata centavos em reais', function () {
    expect(Money::format(123456))->toBe('1.234,56');
});

// R6: data dd/mm/aaaa, passada ou futura, dia e mês sem zero à esquerda aceitos.
it('lê datas válidas', function () {
    expect(BrDate::parse('10/09/2026')->toDateString())->toBe('2026-09-10')
        ->and(BrDate::parse('1/9/2026')->toDateString())->toBe('2026-09-01');
});

it('recusa datas inexistentes ou fora do formato', function (string $raw) {
    expect(BrDate::parse($raw))->toBeNull();
})->with(['31/02/2026', '2026-09-10', '10/13/2026', 'ontem']);
