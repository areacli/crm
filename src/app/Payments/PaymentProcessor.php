<?php

namespace App\Payments;

use App\Enums\PartialPaymentPolicy;
use App\Enums\WithdrawnPaymentPolicy;
use App\Models\Credit;
use App\Models\Import;
use App\Models\Payment;
use App\Models\TenantSettings;
use Illuminate\Support\Facades\DB;

/**
 * Aplica (ou só simula) os pagamentos de uma importação sobre a carteira (R46, R46a, R50 a R53): em ordem de data
 * de pagamento, com os pendentes cujo título já existe (R52), em lotes. A conferência chama com `commit = false` e
 * recebe os mesmos números que a confirmação vai gravar.
 */
final class PaymentProcessor
{
    private const int CHUNK = 2000;

    /**
     * @return array<string, int>
     */
    public function run(Import $import, bool $commit): array
    {
        $tenantId = $import->tenant_id;
        $settings = TenantSettings::query()->where('tenant_id', $tenantId)->firstOrFail();
        $summary = ['settled' => 0, 'partial' => 0, 'credits' => 0, 'credit_cents' => 0, 'pending_new' => 0, 'pending_applied' => 0, 'applied_cents' => 0, 'pending_cents' => 0];

        $this->buildStream($tenantId, $import->id);
        $total = (int) DB::selectOne('select count(*) as n from payment_stream')->n;

        // Estado dos títulos que recebem mais de um pagamento no fluxo (só esses precisam atravessar os lotes: com 200 mil
        // títulos, guardar o estado de todos estoura a memória). Os demais usam o valor lido do banco.
        /** @var array<int, array{0: int, 1: string, 2: ?string}> $memo */
        $memo = [];

        for ($from = 1; $from <= $total; $from += self::CHUNK) {
            $rows = DB::select('select * from payment_stream where n between ? and ? order by n', [$from, $from + self::CHUNK - 1]);
            $newPayments = [];
            $updates = [];
            $credits = [];
            $bills = [];

            foreach ($rows as $row) {
                if ($row->bill_id === null) {
                    // R52a: o título informado não está na carteira do credor: pendente, sem efeito e sem crédito.
                    if ($row->src === 1) {
                        $summary['pending_new']++;
                        $summary['pending_cents'] += $row->amount_cents;
                        $newPayments[] = $this->paymentRow($tenantId, $import->id, $row, null, Payment::PENDING, 0, 0);
                    }

                    continue;
                }

                $billId = (int) $row->bill_id;
                [$billPaid, $billStatus, $billPaidOn] = $memo[$billId] ?? [(int) $row->paid_cents, $row->bill_status, $bills[$billId]['paid_on'] ?? null];
                [$applied, $credit, $reason, $settled] = $this->allocate($settings, (int) $row->bill_amount, $billStatus, $billPaid, (int) $row->amount_cents);
                $billPaid += $applied;
                if ($settled) {
                    $billStatus = 'paid';
                    $billPaidOn = $row->paid_on;
                    $summary['settled']++;
                } elseif ($applied > 0) {
                    $summary['partial']++;
                }
                $bills[$billId] = ['paid' => $billPaid, 'status' => $billStatus, 'paid_on' => $billPaidOn];
                if ($row->repeats > 1) {
                    $memo[$billId] = [$billPaid, $billStatus, $billPaidOn];
                }
                $summary['applied_cents'] += $applied;
                if ($credit > 0) {
                    $summary['credits']++;
                    $summary['credit_cents'] += $credit;
                }
                if ($row->src === 0) {
                    $summary['pending_applied']++;
                    $updates[] = [$row->payment_id, $row->bill_id, $applied, $credit];
                } else {
                    $newPayments[] = $this->paymentRow($tenantId, $import->id, $row, (int) $row->bill_id, Payment::APPLIED, $applied, $credit);
                }
                if ($credit > 0) {
                    $credits[] = ['contract_id' => (int) $row->contract_id, 'key' => $row->src === 0 ? 'p'.$row->payment_id : $row->channel_id.'|'.$row->identifier, 'amount' => $credit, 'reason' => $reason];
                }
            }

            if ($commit) {
                $this->write($import, $newPayments, $updates, $credits, $bills);
            }
        }

        return $summary;
    }

    /**
     * Decide o que um pagamento faz num título, dado o estado dele nesta execução.
     *
     * @return array{0: int, 1: int, 2: string, 3: bool} aplicado ao título, crédito, motivo do crédito, se quitou
     */
    private function allocate(TenantSettings $settings, int $billAmount, string $status, int $paid, int $amount): array
    {
        $balance = $billAmount - $paid;

        if ($status === 'paid' || $balance <= 0) {
            return [0, $amount, 'already_paid', false];
        }
        if ($status === 'withdrawn' && $settings->withdrawn_payment_policy === WithdrawnPaymentPolicy::Credit) {
            return [0, $amount, 'withdrawn', false];
        }
        if ($amount >= $balance) {
            return [$balance, $amount - $balance, 'excess', true];
        }
        if ($settings->partial_payment_policy === PartialPaymentPolicy::Credit) {
            return [0, $amount, 'without_settling', false];
        }

        return [$amount, 0, 'excess', false];
    }

    /** @return array<string, mixed> */
    private function paymentRow(int $tenantId, int $importId, object $row, ?int $billId, string $status, int $applied, int $credit): array
    {
        return [
            'tenant_id' => $tenantId, 'channel_id' => $row->channel_id, 'import_id' => $importId, 'identifier' => $row->identifier,
            'document' => $row->document, 'bill_number' => $row->bill_number, 'bill_id' => $billId, 'paid_on' => $row->paid_on,
            'amount_cents' => $row->amount_cents, 'method' => $row->method, 'status' => $status, 'applied_cents' => $applied,
            'credit_cents' => $credit, 'reversed_cents' => 0, 'credit_reversed_cents' => 0, 'created_at' => now(), 'updated_at' => now(),
        ];
    }

    /**
     * @param  list<array<string, mixed>>  $newPayments
     * @param  list<array{0: int, 1: int, 2: int, 3: int}>  $updates
     * @param  list<array<string, mixed>>  $credits
     * @param  array<int, array{paid: int, status: string, paid_on: ?string}>  $bills
     */
    private function write(Import $import, array $newPayments, array $updates, array $credits, array $bills): void
    {
        $maxId = (int) DB::table('payments')->max('id');
        if ($newPayments !== []) {
            DB::table('payments')->insert($newPayments);
        }
        $ids = [];
        foreach (DB::table('payments')->where('id', '>', $maxId)->where('import_id', $import->id)->get(['id', 'channel_id', 'identifier']) as $p) {
            $ids[$p->channel_id.'|'.$p->identifier] = $p->id;
        }

        foreach ($updates as [$paymentId, $billId, $applied, $credit]) {
            DB::table('payments')->where('id', $paymentId)->update(['bill_id' => $billId, 'status' => Payment::APPLIED, 'applied_cents' => $applied, 'credit_cents' => $credit, 'import_id' => $import->id, 'updated_at' => now()]);
        }

        $creditRows = [];
        $changes = [];
        foreach ($credits as $c) {
            $creditRows[] = [
                'tenant_id' => $import->tenant_id, 'contract_id' => $c['contract_id'], 'payment_id' => str_starts_with($c['key'], 'p') ? (int) substr($c['key'], 1) : $ids[$c['key']] ?? null,
                'user_id' => $import->user_id, 'kind' => Credit::ENTRY, 'amount_cents' => $c['amount'], 'reason' => $c['reason'], 'occurred_at' => now(),
            ];
            $changes[] = $this->change($import, 'contract', $c['contract_id'], 'credit_added', null, (string) $c['amount']);
        }
        foreach (array_chunk($creditRows, 2000) as $chunk) {
            DB::table('credits')->insert($chunk);
        }

        foreach ($bills as $billId => $b) {
            $changes[] = $this->change($import, 'bill', $billId, 'payment_applied', null, (string) $b['paid']);
        }
        foreach (array_chunk($changes, 2000) as $chunk) {
            DB::table('changes')->insert($chunk);
        }

        foreach (array_chunk($bills, 2000, true) as $chunk) {
            $values = [];
            $bindings = [];
            foreach ($chunk as $billId => $b) {
                $values[] = '(?::bigint, ?::bigint, ?::varchar, ?::date)';
                array_push($bindings, $billId, $b['paid'], $b['status'], $b['paid_on']);
            }
            DB::update(
                'update bills set paid_cents = v.paid, status = v.status, paid_on = v.paid_on, updated_at = now()
                 from (values '.implode(',', $values).') as v(id, paid, status, paid_on) where bills.id = v.id',
                $bindings,
            );
        }
    }

    /** @return array<string, mixed> */
    private function change(Import $import, string $subject, int $id, string $event, ?string $before, ?string $after): array
    {
        return [
            'tenant_id' => $import->tenant_id, 'user_id' => $import->user_id, 'import_id' => $import->id, 'subject_type' => $subject,
            'subject_id' => $id, 'event' => $event, 'field' => null, 'before' => $before, 'after' => $after, 'occurred_at' => now(),
        ];
    }

    /** Fluxo ordenado: as linhas novas da importação e os pagamentos pendentes (R52), por data e linha (R53). */
    private function buildStream(int $tenantId, int $importId): void
    {
        DB::statement('drop table if exists payment_stream');
        DB::statement(<<<'SQL'
            create temporary table payment_stream on commit drop as
            select row_number() over (order by s.paid_on, s.src, s.line) as n,
                   s.src, s.line, s.payment_id, s.channel_id, s.identifier, s.document, s.bill_number, s.paid_on, s.amount_cents, s.method,
                   b.id as bill_id, count(*) over (partition by b.id) as repeats, b.contract_id, b.amount_cents as bill_amount, b.paid_cents, b.status as bill_status
            from (
                select 1 as src, r.line, null::bigint as payment_id, ch.id as channel_id, r.identifier, r.document, r.bill_number,
                       r.paid_on, r.amount_cents, r.method
                from payment_rows r
                join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
                where r.import_id = ? and r.ok
                union all
                select 0, 0, p.id, p.channel_id, p.identifier, p.document, p.bill_number, p.paid_on,
                       p.amount_cents - p.reversed_cents, p.method
                from payments p
                where p.tenant_id = ? and p.status = 'pending' and p.amount_cents - p.reversed_cents > 0
            ) s
            left join customers c on c.tenant_id = ? and c.document = s.document
            left join bills b on b.tenant_id = ? and b.customer_id = c.id and b.number = s.bill_number
        SQL, [$tenantId, $importId, $tenantId, $tenantId, $tenantId]);
        DB::statement('create unique index on payment_stream (n)');
        DB::statement('analyze payment_stream');
    }
}
