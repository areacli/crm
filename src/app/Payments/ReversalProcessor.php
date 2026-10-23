<?php

namespace App\Payments;

use App\Enums\WithdrawnReversalPolicy;
use App\Models\Credit;
use App\Models\Import;
use App\Models\TenantSettings;
use Illuminate\Support\Facades\DB;

/**
 * Aplica (ou só simula) os estornos de uma importação (R60 a R63): o valor estornado sai primeiro do crédito que
 * o pagamento gerou e, depois, do título, que volta à cobrança sozinho se estava pago (R62, R62a).
 */
final class ReversalProcessor
{
    private const int CHUNK = 2000;

    /** @return array<string, int> */
    public function run(Import $import, bool $commit): array
    {
        $tenantId = $import->tenant_id;
        $settings = TenantSettings::query()->where('tenant_id', $tenantId)->firstOrFail();
        $summary = ['reopened' => 0, 'credit_reduced' => 0, 'pending_reduced' => 0, 'from_bill_cents' => 0, 'from_credit_cents' => 0, 'reversed_cents' => 0];

        DB::statement('drop table if exists reversal_stream');
        DB::statement(<<<'SQL'
            create temporary table reversal_stream on commit drop as
            select row_number() over (order by r.paid_on, r.line) as n, r.line, r.identifier, r.paid_on as reversed_on, r.amount_cents, r.reason,
                   p.id as payment_id, p.channel_id, p.status as payment_status, p.amount_cents as payment_amount, p.applied_cents, p.credit_cents,
                   p.reversed_cents, p.credit_reversed_cents, p.bill_id, b.contract_id, b.paid_cents, b.status as bill_status, b.withdrawn_at, b.amount_cents as bill_amount
            from payment_rows r
            join payment_channels ch on ch.tenant_id = ? and ch.code = r.channel_code
            join payments p on p.tenant_id = ? and p.channel_id = ch.id and p.identifier = r.payment_identifier
            left join bills b on b.id = p.bill_id
            where r.import_id = ? and r.ok
        SQL, [$tenantId, $tenantId, $import->id]);
        DB::statement('create unique index on reversal_stream (n)');
        DB::statement('analyze reversal_stream');
        $total = (int) DB::selectOne('select count(*) as n from reversal_stream')->n;

        /** @var array<int, array{reversed: int, credit_reversed: int, status: string}> $payments */
        $payments = [];
        /** @var array<int, array{paid: int, status: string, paid_on: ?string}> $bills */
        $bills = [];

        for ($from = 1; $from <= $total; $from += self::CHUNK) {
            $rows = DB::select('select * from reversal_stream where n between ? and ? order by n', [$from, $from + self::CHUNK - 1]);
            $reversals = [];
            $credits = [];
            $changes = [];
            $touchedPayments = [];
            $touchedBills = [];

            foreach ($rows as $row) {
                $p = $payments[$row->payment_id] ??= ['reversed' => (int) $row->reversed_cents, 'credit_reversed' => (int) $row->credit_reversed_cents, 'status' => $row->payment_status];
                $amount = (int) $row->amount_cents;
                $summary['reversed_cents'] += $amount;
                $fromCredit = 0;
                $fromBill = 0;

                if ($row->bill_id === null) {
                    // Pagamento pendente estornado deixa de ser pendente pelo valor estornado (R62).
                    $summary['pending_reduced']++;
                } else {
                    $fromCredit = min($amount, (int) $row->credit_cents - $p['credit_reversed']);
                    $fromBill = $amount - $fromCredit;
                    $p['credit_reversed'] += $fromCredit;
                    if ($fromCredit > 0) {
                        $summary['credit_reduced']++;
                        $summary['from_credit_cents'] += $fromCredit;
                        $credits[] = [
                            'tenant_id' => $tenantId, 'contract_id' => (int) $row->contract_id, 'payment_id' => (int) $row->payment_id, 'user_id' => $import->user_id,
                            'kind' => Credit::REVERSAL, 'amount_cents' => -$fromCredit, 'reason' => 'reversal', 'occurred_at' => now(),
                        ];
                    }
                    if ($fromBill > 0) {
                        $bill = $bills[$row->bill_id] ??= ['paid' => (int) $row->paid_cents, 'status' => $row->bill_status, 'paid_on' => null];
                        $bill['paid'] -= $fromBill;
                        $summary['from_bill_cents'] += $fromBill;
                        if ($bill['status'] === 'paid') {
                            // R62a: o título que o credor tinha retirado segue a política; os demais voltam à cobrança.
                            $bill['status'] = $row->withdrawn_at !== null && $settings->withdrawn_reversal_policy === WithdrawnReversalPolicy::Withdrawn ? 'withdrawn' : 'active';
                            $bill['paid_on'] = null;
                            $summary['reopened']++;
                        }
                        $bills[$row->bill_id] = $bill;
                        $touchedBills[$row->bill_id] = true;
                        $changes[] = ['subject_type' => 'bill', 'subject_id' => (int) $row->bill_id, 'event' => 'payment_reversed', 'after' => (string) $bill['paid']];
                    }
                }

                $p['reversed'] += $amount;
                if ($row->bill_id === null && $p['reversed'] >= (int) $row->payment_amount) {
                    $p['status'] = 'cancelled';
                }
                $payments[$row->payment_id] = $p;
                $touchedPayments[$row->payment_id] = true;
                $reversals[] = [
                    'tenant_id' => $tenantId, 'channel_id' => $row->channel_id, 'payment_id' => $row->payment_id, 'import_id' => $import->id,
                    'identifier' => $row->identifier, 'reversed_on' => $row->reversed_on, 'amount_cents' => $amount,
                    'from_credit_cents' => $fromCredit, 'from_bill_cents' => $fromBill, 'reason' => $row->reason, 'created_at' => now(), 'updated_at' => now(),
                ];
            }

            if ($commit) {
                $this->write($import, $reversals, $credits, $changes, array_intersect_key($payments, $touchedPayments), array_intersect_key($bills, $touchedBills));
            }
        }

        return $summary;
    }

    /**
     * @param  list<array<string, mixed>>  $reversals
     * @param  list<array<string, mixed>>  $credits
     * @param  list<array<string, mixed>>  $changes
     * @param  array<int, array{reversed: int, credit_reversed: int, status: string}>  $payments
     * @param  array<int, array{paid: int, status: string, paid_on: ?string}>  $bills
     */
    private function write(Import $import, array $reversals, array $credits, array $changes, array $payments, array $bills): void
    {
        foreach (array_chunk($reversals, 2000) as $chunk) {
            DB::table('payment_reversals')->insert($chunk);
        }
        foreach (array_chunk($credits, 2000) as $chunk) {
            DB::table('credits')->insert($chunk);
        }
        $rows = array_map(fn (array $c) => $c + ['tenant_id' => $import->tenant_id, 'user_id' => $import->user_id, 'import_id' => $import->id, 'field' => null, 'before' => null, 'occurred_at' => now()], $changes);
        foreach (array_chunk($rows, 2000) as $chunk) {
            DB::table('changes')->insert($chunk);
        }

        foreach (array_chunk($payments, 2000, true) as $chunk) {
            $values = [];
            $bindings = [];
            foreach ($chunk as $id => $p) {
                $values[] = '(?::bigint, ?::bigint, ?::bigint, ?::varchar)';
                array_push($bindings, $id, $p['reversed'], $p['credit_reversed'], $p['status']);
            }
            DB::update(
                'update payments set reversed_cents = v.reversed, credit_reversed_cents = v.credit_reversed, status = v.status, updated_at = now()
                 from (values '.implode(',', $values).') as v(id, reversed, credit_reversed, status) where payments.id = v.id',
                $bindings,
            );
        }
        foreach (array_chunk($bills, 2000, true) as $chunk) {
            $values = [];
            $bindings = [];
            foreach ($chunk as $id => $b) {
                $values[] = '(?::bigint, ?::bigint, ?::varchar, ?::date)';
                array_push($bindings, $id, $b['paid'], $b['status'], $b['paid_on']);
            }
            DB::update(
                'update bills set paid_cents = v.paid, status = v.status, paid_on = v.paid_on, updated_at = now()
                 from (values '.implode(',', $values).') as v(id, paid, status, paid_on) where bills.id = v.id',
                $bindings,
            );
        }
    }
}
