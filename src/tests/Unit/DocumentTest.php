<?php

use App\Support\Document;

// R1: o documento é identificado sem máscara.
it('normaliza o documento sem máscara', function () {
    expect(Document::normalize('529.982.247-25'))->toBe('52998224725')
        ->and(Document::normalize('52998224725'))->toBe('52998224725');
});

// R2: dígitos verificadores válidos.
it('aceita CPF válido, com ou sem máscara', function () {
    expect(Document::problem('529.982.247-25'))->toBeNull()
        ->and(Document::problem('52998224725'))->toBeNull();
});

it('recusa CPF com todos os dígitos iguais', function () {
    expect(Document::problem('111.111.111-11'))->toBe('CPF inválido');
});

it('recusa CPF com dígito verificador errado', function () {
    expect(Document::problem('529.982.247-26'))->toBe('CPF inválido');
});

it('aceita CNPJ numérico válido', function () {
    expect(Document::problem('11.222.333/0001-81'))->toBeNull();
});

it('aceita CNPJ alfanumérico válido (exemplo da Receita Federal)', function () {
    expect(Document::problem('12.ABC.345/01DE-35'))->toBeNull();
});

it('recusa CNPJ alfanumérico com dígito verificador errado', function () {
    expect(Document::problem('12.ABC.345/01DE-36'))->toBe('CNPJ inválido');
});

it('recusa documento com tamanho que não é CPF nem CNPJ', function () {
    expect(Document::problem('12345'))->toStartWith('documento inválido');
});

it('mascara CPF e CNPJ na lista', function () {
    expect(Document::mask('52998224725'))->toBe('529.***.***-25')
        ->and(Document::mask('12ABC34501DE35'))->toBe('12.***.***/****-35');
});
