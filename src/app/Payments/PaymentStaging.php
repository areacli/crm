<?php

namespace App\Payments;

use Illuminate\Support\Facades\DB;

/** Grava as linhas válidas da conferência de pagamentos ou estornos na tabela de preparação, em lote (COPY). */
final class PaymentStaging
{
    private const string COLUMNS = 'import_id,line,channel_code,identifier,document,bill_number,paid_on,amount_cents,method,payment_identifier,reason,ok';

    /** @var list<string> */
    private array $buffer = [];

    public function __construct(private readonly int $importId, private readonly int $batchSize = 5000) {}

    /** @param  array<string, mixed>  $values  chaves da tabela payment_rows; as ausentes ficam nulas */
    public function add(int $line, array $values, bool $ok = true): void
    {
        $row = [$this->importId, $line];
        foreach (['channel_code', 'identifier', 'document', 'bill_number', 'paid_on', 'amount_cents', 'method', 'payment_identifier', 'reason'] as $column) {
            $row[] = $values[$column] ?? null;
        }
        $row[] = $ok ? 't' : 'f';
        $this->buffer[] = implode("\t", array_map(fn ($v) => $v === null ? '\\N' : strtr((string) $v, ['\\' => '\\\\', "\t" => '\\t', "\n" => '\\n', "\r" => '\\r']), $row));
        if (count($this->buffer) >= $this->batchSize) {
            $this->flush();
        }
    }

    public function flush(): void
    {
        if ($this->buffer === []) {
            return;
        }
        DB::connection()->getPdo()->pgsqlCopyFromArray('payment_rows', $this->buffer, "\t", '\\\\N', self::COLUMNS);
        $this->buffer = [];
    }
}
