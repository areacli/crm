<?php

namespace App\Import;

use Illuminate\Support\Facades\DB;

/** Grava as linhas da conferência na tabela de preparação, em lote, pelo COPY do PostgreSQL. */
final class Staging
{
    private const string COLUMNS = 'import_id,line,document,number,name,name_key,phone,email,contract,due_date,amount_cents,description,ok,keep_document,roles';

    /** @var list<string> */
    private array $buffer = [];

    public function __construct(private readonly int $importId, private readonly int $batchSize = 5000) {}

    public function add(ParsedRow $row, string $nameKey): void
    {
        $this->push([
            $this->importId, $row->line, $row->document, $row->number, $row->name, $nameKey,
            $row->phone, $row->email, $row->contract, $row->dueDate, $row->amountCents, $row->description, 't', 'f', $row->roles,
        ]);
    }

    /** Linha recusada, mas com documento e título legíveis: guarda a chave para o título não ser retirado (R15). */
    public function addKeyOnly(int $line, string $document, string $number): void
    {
        $this->push([$this->importId, $line, $document, $number, null, null, null, null, null, null, null, null, 'f', 'f', null]);
    }

    public function flush(): void
    {
        if ($this->buffer === []) {
            return;
        }
        DB::connection()->getPdo()->pgsqlCopyFromArray('import_rows', $this->buffer, "\t", '\\\\N', self::COLUMNS);
        $this->buffer = [];
    }

    /** @param list<int|string|null> $values */
    private function push(array $values): void
    {
        $this->buffer[] = implode("\t", array_map(fn ($v) => $v === null ? '\\N' : $this->escape((string) $v), $values));
        if (count($this->buffer) >= $this->batchSize) {
            $this->flush();
        }
    }

    /** Escapa os caracteres especiais do formato texto do COPY. */
    private function escape(string $value): string
    {
        return strtr($value, ['\\' => '\\\\', "\t" => '\\t', "\n" => '\\n', "\r" => '\\r']);
    }
}
