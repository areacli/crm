<?php

namespace App\Import;

/**
 * Colunas da planilha de carteira para a tela (R44): nome, se é obrigatória, formato e exemplo. Um teste confere que
 * esta lista e a leitura (`CsvFile`) tratam as mesmas colunas, para a tela e a conferência nunca divergirem.
 */
final class CsvColumns
{
    /** @return list<array{name: string, required: bool, format: string, example: string}> */
    public static function all(): array
    {
        return [
            ['name' => 'documento', 'required' => true, 'format' => 'CPF ou CNPJ, com ou sem pontuação', 'example' => '529.982.247-25'],
            ['name' => 'nome', 'required' => true, 'format' => 'Texto, até 300 caracteres', 'example' => 'Maria da Silva'],
            ['name' => 'titulo', 'required' => true, 'format' => 'Número do título, até 100 caracteres', 'example' => 'T-1001'],
            ['name' => 'vencimento', 'required' => true, 'format' => 'Data dd/mm/aaaa', 'example' => '10/09/2026'],
            ['name' => 'valor', 'required' => true, 'format' => 'Reais, com vírgula nos centavos', 'example' => '1.250,00'],
            ['name' => 'telefone', 'required' => false, 'format' => 'Com DDD, até 60 caracteres', 'example' => '(11) 98888-7777'],
            ['name' => 'email', 'required' => false, 'format' => 'E-mail válido', 'example' => 'maria@exemplo.com.br'],
            ['name' => 'contrato', 'required' => false, 'format' => 'Código do contrato, até 100 caracteres; vazio cria um contrato por omissão', 'example' => 'C-2026-01'],
            ['name' => 'descricao', 'required' => false, 'format' => 'Texto, até 300 caracteres', 'example' => 'Mensalidade de setembro'],
            ['name' => 'papel', 'required' => false, 'format' => 'titular, responsavel financeiro ou os dois separados por barra; vazio vale os dois', 'example' => 'titular'],
        ];
    }

    /** Planilha-modelo: cabeçalho e três linhas fictícias que passam na conferência sem recusa. */
    public static function templateCsv(): string
    {
        $names = array_column(self::all(), 'name');
        $rows = [
            ['529.982.247-25', 'Maria da Silva', 'T-1001', '10/09/2026', '1.250,00', '(11) 98888-7777', 'maria@exemplo.com.br', 'C-2026-01', 'Mensalidade de setembro', 'titular'],
            ['390.533.447-05', 'João Pereira', 'T-1002', '15/09/2026', '980,50', '(21) 97777-6666', 'joao@exemplo.com.br', 'C-2026-02', 'Mensalidade de setembro', ''],
            ['111.444.777-35', 'Ana Souza', 'T-1003', '05/10/2026', '1.250,00', '', '', 'C-2026-03', 'Matrícula', ''],
        ];

        return "\u{FEFF}".implode("\n", array_map(fn (array $row) => implode(';', $row), [$names, ...$rows]))."\n";
    }
}
