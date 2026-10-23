<?php

namespace App\Import;

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Models\Import;
use App\Support\Document;
use App\Support\Money;
use App\Support\Text;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Conferência da importação (R10): lê o arquivo, valida linha a linha, grava na tabela de preparação e
 * compara com a carteira. Nada toca a carteira: só a preparação, as recusas e o resumo da importação.
 */
final class ImportChecker
{
    private const int PROGRESS_EVERY = 5000;

    public function __construct(private readonly RowValidator $validator = new RowValidator) {}

    public function run(Import $import): void
    {
        $import->update(['status' => ImportStatus::Checking, 'progress_percent' => 1, 'progress_label' => 'Lendo o arquivo']);
        $this->clean($import);

        try {
            $summary = $this->check($import);
        } catch (ImportRefused $e) {
            $this->clean($import);
            $import->update([
                'status' => ImportStatus::Rejected,
                'failure_reason' => $e->getMessage(),
                'finished_at' => now(),
                'progress_percent' => 100,
                'progress_label' => null,
            ]);
            Storage::disk('local')->delete($import->stored_path);

            return;
        }

        $import->update([
            'status' => ImportStatus::Checked,
            'summary' => $summary,
            'checked_at' => now(),
            'progress_percent' => 100,
            'progress_label' => null,
        ]);
    }

    private function clean(Import $import): void
    {
        DB::table('import_rows')->where('import_id', $import->id)->delete();
        DB::table('import_rejections')->where('import_id', $import->id)->delete();
    }

    /** @return array<string, mixed> */
    private function check(Import $import): array
    {
        $path = Storage::disk('local')->path($import->stored_path);
        $file = new CsvFile($path);
        $staging = new Staging($import->id);

        $lines = 0;
        $valid = 0;
        $rejected = [];
        $total = max(1, (int) (filesize($path) / 90));

        foreach ($file->rows() as $line => $row) {
            $lines++;
            [$parsed, $reason] = $this->validator->validate($line, $row);

            if ($parsed !== null) {
                $valid++;
                $staging->add($parsed, Text::fold($parsed->name));
            } else {
                $rejected[] = ['import_id' => $import->id, 'line' => $line, 'reason' => $reason];
                // Mantém a chave do título para ele não ser retirado no batimento (R15).
                $document = Document::normalize($row['documento'] ?? '');
                if (Document::problem($row['documento'] ?? '') === null && ($row['titulo'] ?? '') !== '') {
                    $staging->addKeyOnly($line, $document, mb_substr($row['titulo'], 0, 100));
                }
            }

            if ($lines % self::PROGRESS_EVERY === 0) {
                $import->update(['progress_percent' => min(60, 1 + (int) (59 * $lines / $total)), 'progress_label' => 'Lendo o arquivo: '.number_format($lines, 0, ',', '.').' linhas']);
            }
        }
        $staging->flush();
        // Tabela recém-carregada não tem estatísticas: sem ANALYZE o planejador subestima o tamanho e escolhe plano ruim.
        DB::statement('analyze import_rows');
        foreach (array_chunk($rejected, 2000) as $chunk) {
            DB::table('import_rejections')->insert($chunk);
        }

        $import->update(['progress_percent' => 65, 'progress_label' => 'Procurando repetições e nomes divergentes']);
        $this->rejectDivergentNames($import);
        $this->rejectDuplicateBills($import);

        $import->update(['progress_percent' => 80, 'progress_label' => 'Comparando com a carteira']);

        return $this->summarize($import, $file, $lines);
    }

    /** R7: nomes diferentes para o mesmo documento no arquivo: todas as linhas do documento são recusadas. */
    private function rejectDivergentNames(Import $import): void
    {
        $bad = DB::select(<<<'SQL'
            select document,
                   array_to_string(array_agg(first_line order by first_line), ',') as firsts
            from (
                select document, name_key, min(line) as first_line
                from import_rows where import_id = ? and ok group by document, name_key
            ) t
            group by document having count(*) > 1
        SQL, [$import->id]);

        foreach (array_chunk($bad, 500) as $chunk) {
            $reasons = [];
            foreach ($chunk as $b) {
                $reasons[$b->document] = __('import.reasons.divergent_names', ['lines' => $this->joinLines(explode(',', $b->firsts))]);
            }
            $values = collect($reasons)->map(fn ($r, $d) => [$d, $r]);

            DB::insert(
                'insert into import_rejections (import_id, line, reason)
                 select r.import_id, r.line, m.reason from import_rows r
                 join (values '.$values->map(fn () => '(?, ?)')->implode(',').') as m(document, reason) on m.document = r.document
                 where r.import_id = ? and r.ok',
                [...$values->flatten()->all(), $import->id],
            );
            DB::update(
                'update import_rows set ok = false, keep_document = true where import_id = ? and document in ('.$values->map(fn () => '?')->implode(',').')',
                [$import->id, ...$values->keys()->all()],
            );
        }
    }

    /** R4: o mesmo título repetido no arquivo: a primeira ocorrência vale e as seguintes são recusadas. */
    private function rejectDuplicateBills(Import $import): void
    {
        DB::insert(<<<'SQL'
            insert into import_rejections (import_id, line, reason)
            select import_id, line, 'título repetido na linha ' || first_line
            from (
                select import_id, line,
                       first_value(line) over w as first_line,
                       row_number() over w as rn
                from import_rows
                where import_id = ? and ok
                window w as (partition by import_id, document, number order by line)
            ) d where rn > 1
        SQL, [$import->id]);

        DB::update(<<<'SQL'
            update import_rows r set ok = false
            from (
                select line from (
                    select line, row_number() over (partition by document, number order by line) as rn
                    from import_rows where import_id = ? and ok
                ) d where rn > 1
            ) dup
            where r.import_id = ? and r.line = dup.line
        SQL, [$import->id, $import->id]);
    }

    /** @param list<string|int> $lines */
    private function joinLines(array $lines): string
    {
        $lines = array_values($lines);
        if (count($lines) <= 1) {
            return (string) ($lines[0] ?? '');
        }
        $last = array_pop($lines);

        return implode(', ', $lines).' e '.$last;
    }

    /** @return array<string, mixed> */
    private function summarize(Import $import, CsvFile $file, int $lines): array
    {
        $tenantId = $import->tenant_id;
        $id = $import->id;

        $ok = DB::selectOne('select count(*) as bills, count(distinct document) as customers, coalesce(sum(amount_cents), 0) as amount from import_rows where import_id = ? and ok', [$id]);

        $existing = DB::selectOne(<<<'SQL'
            select
                count(*) filter (where b.id is null) as bills_new,
                count(*) filter (where b.id is not null and b.status = 'active' and
                    (b.amount_cents <> r.amount_cents or b.due_date <> r.due_date or b.description is distinct from r.description or
                     coalesce(k.code, '') <> coalesce(r.contract, ''))) as bills_updated,
                count(*) filter (where b.id is not null and b.status = 'active' and
                    b.amount_cents = r.amount_cents and b.due_date = r.due_date and b.description is not distinct from r.description and
                    coalesce(k.code, '') = coalesce(r.contract, '')) as bills_unchanged,
                count(*) filter (where b.status = 'withdrawn') as bills_reincluded,
                count(*) filter (where b.status = 'paid') as bills_paid_kept
            from import_rows r
            left join customers c on c.tenant_id = ? and c.document = r.document
            left join bills b on b.tenant_id = ? and b.customer_id = c.id and b.number = r.number
            left join contracts k on k.id = b.contract_id
            where r.import_id = ? and r.ok
        SQL, [$tenantId, $tenantId, $id]);

        $newCustomers = DB::selectOne(
            'select count(*) as n from (select distinct document from import_rows where import_id = ? and ok) d
             where not exists (select 1 from customers c where c.tenant_id = ? and c.document = d.document)',
            [$id, $tenantId],
        )->n;

        $withdraw = ['count' => 0, 'amount_cents' => 0];
        $kept = 0;
        if ($import->mode === ImportMode::FullSync) {
            $w = DB::selectOne(<<<'SQL'
                select count(*) as n, coalesce(sum(b.amount_cents), 0) as amount
                from bills b join customers c on c.id = b.customer_id
                where b.tenant_id = ? and b.status = 'active' and not exists (
                    select 1 from import_rows r where r.import_id = ? and r.document = c.document and (r.number = b.number or r.keep_document))
            SQL, [$tenantId, $id]);
            $withdraw = ['count' => (int) $w->n, 'amount_cents' => (int) $w->amount];

            // R15: título gravado cuja linha foi recusada não é retirado.
            $kept = DB::selectOne(<<<'SQL'
                select count(*) as n from bills b join customers c on c.id = b.customer_id
                where b.tenant_id = ? and b.status = 'active' and exists (
                    select 1 from import_rows r where r.import_id = ? and not r.ok and r.document = c.document and (r.number = b.number or r.keep_document))
                  and not exists (select 1 from import_rows r where r.import_id = ? and r.ok and r.document = c.document and r.number = b.number)
            SQL, [$tenantId, $id, $id])->n;
        }

        $omitted = (int) DB::selectOne(
            'select count(distinct document) as n from import_rows where import_id = ? and ok and contract is null',
            [$id],
        )->n;

        // R9b: contratos com mais de um cliente na carga e linhas que declaram papel.
        $multiCustomer = (int) DB::selectOne(
            'select count(*) as n from (select contract from import_rows where import_id = ? and ok and contract is not null
             group by contract having count(distinct document) > 1) t',
            [$id],
        )->n;
        $rolesDeclared = (int) DB::selectOne('select count(*) as n from import_rows where import_id = ? and ok and roles is not null', [$id])->n;

        return [
            'lines' => $lines,
            'valid' => (int) $ok->bills,
            'rejected' => (int) DB::table('import_rejections')->where('import_id', $id)->count(),
            'blank_lines' => $file->blankLines,
            'ignored_columns' => $file->ignoredColumns,
            'customers' => (int) $ok->customers,
            'customers_new' => (int) $newCustomers,
            'amount_cents' => (int) $ok->amount,
            'bills_new' => (int) $existing->bills_new,
            'bills_updated' => (int) $existing->bills_updated,
            'bills_unchanged' => (int) $existing->bills_unchanged,
            'bills_reincluded' => (int) $existing->bills_reincluded,
            'bills_paid_kept' => (int) $existing->bills_paid_kept,
            'to_withdraw' => $withdraw,
            'kept_by_rejection' => (int) $kept,
            'contracts_created_by_omission' => $omitted,
            'contracts_multi_customer' => $multiCustomer,
            'roles_declared' => $rolesDeclared,
            'amount_formatted' => Money::format((int) $ok->amount),
        ];
    }
}
