<?php

namespace App\Import;

use App\Support\Text;
use Generator;

/**
 * Leitor do CSV da carteira: separador `;`, UTF-8 ou Windows-1252, cabeçalho obrigatório com as colunas
 * em qualquer ordem, sem diferenciar maiúsculas nem acentos (formato da planilha, especificação 01).
 * Lê linha a linha, sem carregar o arquivo inteiro.
 */
final class CsvFile
{
    public const array REQUIRED = ['documento', 'nome', 'titulo', 'vencimento', 'valor'];

    public const array OPTIONAL = ['telefone', 'email', 'contrato', 'descricao', 'papel'];

    public const int MAX_BYTES = 50 * 1024 * 1024;

    public const int MAX_LINES = 200_000;

    /** @var resource */
    private $handle;

    /** @var array<int, string> posição da coluna => nome normalizado */
    private array $columns = [];

    /** @var list<string> colunas do cabeçalho que o sistema não conhece (ignoradas e listadas no relatório) */
    public array $ignoredColumns = [];

    public int $blankLines = 0;

    private bool $latin1 = false;

    public function __construct(private readonly string $path)
    {
        if (filesize($path) > self::MAX_BYTES) {
            throw new ImportRefused('arquivo acima do limite de 50 MB');
        }

        $handle = fopen($path, 'rb');
        if ($handle === false) {
            throw new ImportRefused('não foi possível ler o arquivo');
        }
        $this->handle = $handle;
        $this->detectEncoding();
        $this->readHeader();
    }

    public function __destruct()
    {
        if (is_resource($this->handle)) {
            fclose($this->handle);
        }
    }

    /**
     * @return Generator<int, array<string, string>> número da linha no arquivo => valores por coluna
     *                                               Linhas com células a mais vêm com a chave "__extra" = true.
     */
    public function rows(): Generator
    {
        $line = 1;
        $count = 0;
        while (($cells = fgetcsv($this->handle, 0, ';', '"', '')) !== false) {
            $line++;
            if ($cells === [null] || $this->allEmpty($cells)) {
                $this->blankLines++;

                continue;
            }
            if (++$count > self::MAX_LINES) {
                throw new ImportRefused('arquivo acima do limite de 200.000 linhas');
            }

            $cells = array_map(fn (?string $c) => $this->decode((string) $c), $cells);
            $row = [];
            $width = count($this->columns);

            // Células a mais: só conta se houver conteúdo além das colunas do cabeçalho.
            $extra = array_slice($cells, $width);
            $row['__extra'] = $this->allEmpty($extra) ? '' : '1';
            $row['__short'] = count($cells) < $width ? '1' : '';

            foreach ($this->columns as $position => $name) {
                $row[$name] = trim($cells[$position] ?? '');
            }
            yield $line => $row;
        }

        if ($count === 0) {
            throw new ImportRefused('arquivo sem linhas de dados');
        }
    }

    private function detectEncoding(): void
    {
        $sample = (string) fread($this->handle, 1024 * 1024);
        rewind($this->handle);

        if (str_contains($sample, "\0")) {
            throw new ImportRefused('o arquivo não parece ser um CSV (contém dados binários)');
        }

        // Um corte no meio de um caractere multibyte da amostra não deve contar como erro.
        $probe = rtrim($sample, "\x80..\xFF");
        if (mb_check_encoding($probe, 'UTF-8')) {
            if (str_contains($sample, "\u{FFFD}")) {
                throw new ImportRefused('caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252');
            }
            $this->latin1 = false;
        } else {
            // Bytes que o Windows-1252 não define indicam outra codificação.
            if (preg_match('/[\x81\x8D\x8F\x90\x9D]/', $sample)) {
                throw new ImportRefused('caracteres ilegíveis: confira se o arquivo foi salvo em UTF-8 ou Windows-1252');
            }
            $this->latin1 = true;
        }

        if (str_starts_with($sample, "\xEF\xBB\xBF")) {
            fseek($this->handle, 3);
        }
    }

    private function decode(string $value): string
    {
        return $this->latin1 ? mb_convert_encoding($value, 'UTF-8', 'Windows-1252') : $value;
    }

    private function readHeader(): void
    {
        $headerLine = fgets($this->handle);
        if ($headerLine === false || trim($headerLine) === '') {
            throw new ImportRefused('arquivo sem linhas de dados');
        }
        $headerLine = $this->decode($headerLine);

        if (substr_count($headerLine, ';') === 0 && substr_count($headerLine, ',') > 0) {
            throw new ImportRefused('separador errado: o arquivo usa vírgula. Salve como "CSV (separado por ponto e vírgula)".');
        }

        $names = str_getcsv(rtrim($headerLine, "\r\n"), ';', '"', '');
        $known = array_merge(self::REQUIRED, self::OPTIONAL);
        foreach ($names as $position => $raw) {
            $name = str_replace(' ', '', Text::fold((string) $raw));
            if (in_array($name, $known, true) && ! in_array($name, $this->columns, true)) {
                $this->columns[$position] = $name;
            } elseif (trim((string) $raw) !== '') {
                $this->ignoredColumns[] = trim((string) $raw);
            }
        }

        $missing = array_values(array_diff(self::REQUIRED, $this->columns));
        if ($missing !== []) {
            throw new ImportRefused('coluna obrigatória ausente: '.implode(', ', $missing));
        }
    }

    /** @param array<int, ?string> $cells */
    private function allEmpty(array $cells): bool
    {
        foreach ($cells as $cell) {
            if (trim((string) $cell) !== '') {
                return false;
            }
        }

        return true;
    }
}
