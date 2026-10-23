<?php

use App\Import\CsvFile;
use App\Import\ImportRefused;

function csv(string $content): string
{
    $path = tempnam(sys_get_temp_dir(), 'csv');
    file_put_contents($path, $content);

    return $path;
}

const HEADER = "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n";

it('lê o cabeçalho em qualquer ordem, sem diferenciar maiúsculas nem acentos', function () {
    $file = new CsvFile(csv("VALOR;Título;VENCIMENTO;Documento;NOME\n10,00;NF-1;10/09/2026;52998224725;Maria\n"));
    $rows = iterator_to_array($file->rows());

    expect($rows)->toHaveCount(1)
        ->and($rows[2]['titulo'])->toBe('NF-1')
        ->and($rows[2]['valor'])->toBe('10,00')
        ->and($rows[2]['documento'])->toBe('52998224725');
});

it('recusa o arquivo inteiro quando falta coluna obrigatória', function () {
    new CsvFile(csv("documento;nome;titulo;valor\n1;2;3;4\n"));
})->throws(ImportRefused::class, 'coluna obrigatória ausente: vencimento');

it('lista as colunas desconhecidas como ignoradas', function () {
    $file = new CsvFile(csv("documento;nome;titulo;vencimento;valor;observacao\n52998224725;Maria;NF-1;10/09/2026;10,00;x\n"));

    expect($file->ignoredColumns)->toBe(['observacao']);
});

it('recusa o separador errado e sugere o formato certo', function () {
    new CsvFile(csv("documento,nome,titulo,vencimento,valor\n1,2,3,4,5\n"));
})->throws(ImportRefused::class, 'separador errado');

it('ignora linhas em branco e conta quantas foram', function () {
    $file = new CsvFile(csv(HEADER."52998224725;Maria;;;;NF-1;10/09/2026;10,00;\n\n;;;;;;;;\n52998224725;Maria;;;;NF-2;10/09/2026;10,00;\n"));
    $rows = iterator_to_array($file->rows());

    expect($rows)->toHaveCount(2)->and($file->blankLines)->toBe(2);
});

it('marca célula preenchida além do cabeçalho, mas não células vazias no fim', function () {
    $file = new CsvFile(csv("documento;nome;titulo;vencimento;valor\n52998224725;Maria;NF-1;10/09/2026;10,00;;\n52998224725;Maria;NF-2;10/09/2026;10,00;sobra\n"));
    $rows = iterator_to_array($file->rows());

    expect($rows[2]['__extra'])->toBe('')->and($rows[3]['__extra'])->toBe('1');
});

it('marca linha com colunas a menos como incompleta', function () {
    $file = new CsvFile(csv("documento;nome;titulo;vencimento;valor\n52998224725;Maria;NF-1\n"));

    expect(iterator_to_array($file->rows())[2]['__short'])->toBe('1');
});

it('lê arquivo em Windows-1252', function () {
    $content = mb_convert_encoding("documento;nome;titulo;vencimento;valor\n52998224725;José Conceição;NF-1;10/09/2026;10,00\n", 'Windows-1252', 'UTF-8');
    $rows = iterator_to_array((new CsvFile(csv($content)))->rows());

    expect($rows[2]['nome'])->toBe('José Conceição');
});

it('lê arquivo UTF-8 com BOM', function () {
    $rows = iterator_to_array((new CsvFile(csv("\xEF\xBB\xBFdocumento;nome;titulo;vencimento;valor\n52998224725;Maria;NF-1;10/09/2026;10,00\n")))->rows());

    expect($rows)->toHaveCount(1);
});

it('recusa arquivo só com cabeçalho', function () {
    iterator_to_array((new CsvFile(csv("documento;nome;titulo;vencimento;valor\n")))->rows());
})->throws(ImportRefused::class, 'arquivo sem linhas de dados');

it('recusa arquivo vazio', function () {
    new CsvFile(csv(''));
})->throws(ImportRefused::class, 'arquivo sem linhas de dados');

it('recusa arquivo com dados binários', function () {
    new CsvFile(csv("documento;nome\0;titulo\n"));
})->throws(ImportRefused::class, 'não parece ser um CSV');
