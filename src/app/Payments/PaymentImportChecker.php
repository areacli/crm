<?php

namespace App\Payments;

use App\Enums\ImportStatus;
use App\Import\CsvFile;
use App\Import\ImportRefused;
use App\Models\Import;
use App\Support\Money;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

/**
 * Conferência da importação de pagamentos ou de estornos (R48 a R56, R60 a R63): lê o arquivo, valida linha a
 * linha, grava na preparação, aplica as regras de unicidade e simula o efeito sobre a carteira, sem gravar nada
 * nela. A confirmação refaz a mesma simulação, numa única transação, e grava.
 */
final class PaymentImportChecker
{
    private const int PROGRESS_EVERY = 5000;

    public function run(Import $import): void
    {
        $import->update(['status' => ImportStatus::Checking, 'progress_percent' => 1, 'progress_label' => 'Lendo o arquivo']);
        $this->clean($import);

        try {
            $summary = $this->check($import);
        } catch (ImportRefused $e) {
            $this->clean($import);
            $import->update(['status' => ImportStatus::Rejected, 'failure_reason' => $e->getMessage(), 'finished_at' => now(), 'progress_percent' => 100, 'progress_label' => null]);
            Storage::disk('local')->delete($import->stored_path);

            return;
        }

        $import->update(['status' => ImportStatus::Checked, 'summary' => $summary, 'checked_at' => now(), 'progress_percent' => 100, 'progress_label' => null]);
    }

    private function clean(Import $import): void
    {
        DB::table('payment_rows')->where('import_id', $import->id)->delete();
        DB::table('import_rejections')->where('import_id', $import->id)->delete();
    }

    /** @return array<string, mixed> */
    private function check(Import $import): array
    {
        $reversals = $import->kind === 'reversals';
        $file = new CsvFile(
            Storage::disk('local')->path($import->stored_path),
            $reversals ? ReversalRowValidator::REQUIRED : PaymentRowValidator::REQUIRED,
            $reversals ? ReversalRowValidator::OPTIONAL : PaymentRowValidator::OPTIONAL,
        );
        $validator = $reversals ? new ReversalRowValidator : new PaymentRowValidator;
        $staging = new PaymentStaging($import->id);
        $rejected = [];
        $lines = 0;
        $total = max(1, (int) (filesize(Storage::disk('local')->path($import->stored_path)) / 80));

        foreach ($file->rows() as $line => $row) {
            $lines++;
            [$parsed, $reason] = $validator->validate($row);
            if ($parsed !== null) {
                $staging->add($line, $parsed);
            } else {
                $rejected[] = ['import_id' => $import->id, 'line' => $line, 'reason' => $reason];
            }
            if ($lines % self::PROGRESS_EVERY === 0) {
                $import->update(['progress_percent' => min(50, 1 + (int) (49 * $lines / $total)), 'progress_label' => 'Lendo o arquivo: '.number_format($lines, 0, ',', '.').' linhas']);
            }
        }
        $staging->flush();
        foreach (array_chunk($rejected, 2000) as $chunk) {
            DB::table('import_rejections')->insert($chunk);
        }
        DB::statement('analyze payment_rows');

        $import->update(['progress_percent' => 55, 'progress_label' => 'Conferindo canais e repetições']);
        $this->rejectUnknownChannels($import, $reversals);
        $this->rejectRepeated($import, $reversals);
        $this->markAlreadyRegistered($import, $reversals);
        if ($reversals) {
            $this->rejectReversalProblems($import);
        }

        $import->update(['progress_percent' => 75, 'progress_label' => 'Simulando o efeito na carteira']);

        return DB::transaction(function () use ($import, $file, $lines, $reversals) {
            $effect = $reversals ? (new ReversalProcessor)->run($import, false) : (new PaymentProcessor)->run($import, false);

            return $this->summarize($import, $file, $lines, $effect);
        });
    }

    /** R49: canal não cadastrado ou desativado (no estorno, canal desativado é aceito, revisão 5). */
    private function rejectUnknownChannels(Import $import, bool $reversals): void
    {
        $active = $reversals ? '' : ' and ch.active';
        $where = "r.import_id = ? and r.ok and not exists (select 1 from payment_channels ch where ch.tenant_id = ? and ch.code = r.channel_code$active)";

        DB::insert("insert into import_rejections (import_id, line, reason) select r.import_id, r.line, 'canal não cadastrado ou desativado' from payment_rows r where $where", [$import->id, $import->tenant_id]);
        DB::update("update payment_rows r set ok = false where $where", [$import->id, $import->tenant_id]);
    }

    /** R48 e R61: o repetido no mesmo arquivo é recusado; vale a primeira ocorrência. */
    private function rejectRepeated(Import $import, bool $reversals): void
    {
        $label = $reversals ? 'estorno repetido na linha ' : 'pagamento repetido na linha ';
        DB::insert(<<<SQL
            insert into import_rejections (import_id, line, reason)
            select import_id, line, '$label' || first_line from (
                select import_id, line, first_value(line) over w as first_line, row_number() over w as rn
                from payment_rows where import_id = ? and ok
                window w as (partition by channel_code, identifier order by line)
            ) d where rn > 1
        SQL, [$import->id]);
        DB::update(<<<'SQL'
            update payment_rows r set ok = false from (
                select line from (select line, row_number() over (partition by channel_code, identifier order by line) as rn
                                  from payment_rows where import_id = ? and ok) d where rn > 1
            ) dup where r.import_id = ? and r.line = dup.line
        SQL, [$import->id, $import->id]);
    }

    /** R48 e R61: já registrado numa importação anterior: a linha é ignorada, sem efeito (não é recusa). */
    private function markAlreadyRegistered(Import $import, bool $reversals): void
    {
        $table = $reversals ? 'payment_reversals' : 'payments';
        DB::update(<<<SQL
            update payment_rows r set ok = false, reason = 'registered'
            from payment_channels ch, $table x
            where r.import_id = ? and r.ok and ch.tenant_id = ? and ch.code = r.channel_code
              and x.tenant_id = ? and x.channel_id = ch.id and x.identifier = r.identifier
        SQL, [$import->id, $import->tenant_id, $import->tenant_id]);
    }

    /** R61: pagamento não encontrado no canal; data anterior ao pagamento; valor maior que o saldo estornável. */
    private function rejectReversalProblems(Import $import): void
    {
        $t = $import->tenant_id;
        $i = $import->id;

        DB::insert(<<<'SQL'
            insert into import_rejections (import_id, line, reason)
            select r.import_id, r.line, 'pagamento não encontrado no canal' from payment_rows r
            join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            where r.import_id = ? and r.ok
              and not exists (select 1 from payments p where p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier)
        SQL, [$t, $i, $t]);
        DB::update(<<<'SQL'
            update payment_rows r set ok = false from payment_channels ch
            where r.import_id = ? and r.ok and ch.tenant_id = ? and ch.code = r.channel_code
              and not exists (select 1 from payments p where p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier)
        SQL, [$i, $t, $t]);

        DB::insert(<<<'SQL'
            insert into import_rejections (import_id, line, reason)
            select r.import_id, r.line, 'data do estorno anterior ao pagamento' from payment_rows r
            join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
            where r.import_id = ? and r.ok and r.paid_on < p.paid_on
        SQL, [$t, $t, $i]);
        DB::update(<<<'SQL'
            update payment_rows r set ok = false from payment_channels ch, payments p
            where r.import_id = ? and r.ok and ch.tenant_id = ? and ch.code = r.channel_code
              and p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier and r.paid_on < p.paid_on
        SQL, [$i, $t, $t]);

        // Valor acima do que ainda não foi estornado do pagamento, somando as linhas do próprio arquivo em ordem.
        $over = DB::select(<<<'SQL'
            select x.line, x.reversible - (x.cum - x.amount_cents) as left_cents from (
                select r.line, r.amount_cents, p.amount_cents - p.reversed_cents as reversible,
                       sum(r.amount_cents) over (partition by p.id order by r.paid_on, r.line) as cum
                from payment_rows r
                join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
                join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
                where r.import_id = ? and r.ok
            ) x where x.cum > x.reversible
        SQL, [$t, $t, $i]);
        foreach (array_chunk($over, 1000) as $chunk) {
            DB::table('import_rejections')->insert(array_map(fn ($o) => ['import_id' => $i, 'line' => $o->line, 'reason' => 'valor maior que o saldo estornável de R$ '.Money::format(max(0, (int) $o->left_cents))], $chunk));
            DB::update('update payment_rows set ok = false where import_id = ? and line in ('.implode(',', array_fill(0, count($chunk), '?')).')', [$i, ...array_map(fn ($o) => $o->line, $chunk)]);
        }
    }

    /**
     * @param  array<string, int>  $effect
     * @return array<string, mixed>
     */
    private function summarize(Import $import, CsvFile $file, int $lines, array $effect): array
    {
        $id = $import->id;
        $ok = DB::selectOne('select count(*) as n, coalesce(sum(amount_cents), 0) as amount from payment_rows where import_id = ? and ok', [$id]);

        return [
            'lines' => $lines,
            'valid' => (int) $ok->n,
            'rejected' => (int) DB::table('import_rejections')->where('import_id', $id)->count(),
            'ignored' => (int) DB::table('payment_rows')->where('import_id', $id)->where('reason', 'registered')->count(),
            'blank_lines' => $file->blankLines,
            'ignored_columns' => $file->ignoredColumns,
            'amount_cents' => (int) $ok->amount,
            'amount_formatted' => Money::format((int) $ok->amount),
            'effect' => $effect,
        ];
    }
}
