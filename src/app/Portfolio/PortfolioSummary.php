<?php

namespace App\Portfolio;

use App\Enums\PaymentMethod;
use App\Enums\Permission;
use App\Enums\ReversalMonthPolicy;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Resumo da carteira de cada credor (R23): totais e duas distribuições por faixa de atraso, em tabela:
 * por cliente (cada cliente na faixa do título mais atrasado, com todo o seu vencido; visão da cobrança)
 * e por título (cada título vencido na faixa do próprio atraso; visão do financeiro).
 * Um resumo por credor, sem somar faixas de credores diferentes (MT-20).
 */
final class PortfolioSummary
{
    private readonly string $reference;

    public function __construct(private readonly User $user, ?Carbon $reference = null)
    {
        $this->reference = ($reference ?? now())->toDateString();
    }

    /** @return list<array<string, mixed>> um item por credor em que o usuário pode consultar a carteira */
    public function perTenant(): array
    {
        $ids = $this->user->tenantIdsWith(Permission::ViewPortfolio);

        return Tenant::query()->with('settings')->whereIn('id', $ids ?: [0])->orderBy('name')->get()
            ->map(fn (Tenant $tenant) => $this->forTenant($tenant))->all();
    }

    /** @return array<string, mixed> */
    public function forTenant(Tenant $tenant): array
    {
        $brackets = AgingBrackets::fromStored($tenant->settings->aging_brackets);
        $ref = $this->reference;

        $totals = DB::selectOne(<<<'SQL'
            select count(distinct customer_id) as customers,
                   count(*) as bills,
                   coalesce(sum(amount_cents - paid_cents) filter (where due_date < ?::date), 0) as overdue_cents,
                   coalesce(sum(amount_cents - paid_cents) filter (where due_date >= ?::date), 0) as upcoming_cents,
                   count(distinct customer_id) filter (where due_date < ?::date) as customers_overdue
            from bills where tenant_id = ? and status = 'active'
        SQL, [$ref, $ref, $ref, $tenant->id]);

        // A data de referência entra uma só vez, por binding, numa CTE; as faixas a repetem em cada WHEN pela coluna.
        $byBill = DB::select(
            'with r as (select ?::date as d) select '.$brackets->sqlIndex('(r.d - due_date)')." as idx, count(*) as n, sum(amount_cents - paid_cents) as cents
             from bills, r where tenant_id = ? and status = 'active' and due_date < r.d group by 1",
            [$ref, $tenant->id],
        );

        $byCustomer = DB::select(
            'with r as (select ?::date as d) select '.$brackets->sqlIndex('max_days')." as idx, count(*) as n, sum(overdue) as cents from (
                select max(r.d - due_date) as max_days, sum(amount_cents - paid_cents) as overdue
                from bills, r where tenant_id = ? and status = 'active' and due_date < r.d group by customer_id
             ) c group by 1",
            [$ref, $tenant->id],
        );

        return [
            'tenant' => $tenant,
            'customers' => (int) $totals->customers,
            'customers_overdue' => (int) $totals->customers_overdue,
            'bills' => (int) $totals->bills,
            'overdue_cents' => (int) $totals->overdue_cents,
            'upcoming_cents' => (int) $totals->upcoming_cents,
            'upcoming_display' => $tenant->settings->upcoming_display,
            'labels' => $brackets->labels(),
            'by_customer' => $this->distribution($brackets, $byCustomer),
            'by_bill' => $this->distribution($brackets, $byBill),
        ] + $this->payments($tenant);
    }

    /**
     * @param  list<object>  $rows
     * @return list<array{label: string, count: int, cents: int}>
     */
    private function distribution(AgingBrackets $brackets, array $rows): array
    {
        $byIndex = collect($rows)->keyBy('idx');

        return array_map(fn (int $i) => [
            'label' => $brackets->label($i),
            'count' => (int) ($byIndex[$i]->n ?? 0),
            'cents' => (int) ($byIndex[$i]->cents ?? 0),
        ], array_keys($brackets->brackets));
    }

    private const array MONTHS = ['janeiro', 'fevereiro', 'março', 'abril', 'maio', 'junho', 'julho', 'agosto', 'setembro', 'outubro', 'novembro', 'dezembro'];

    /**
     * Valor recuperado no mês corrente e no anterior, por meio de pagamento (R58, R64), créditos do credor somando
     * cada contrato uma vez (R55b) e pagamentos pendentes. Crédito e pendente não contam como recuperado.
     *
     * @return array<string, mixed>
     */
    private function payments(Tenant $tenant): array
    {
        $ref = Carbon::parse($this->reference);
        $months = [$ref->copy()->startOfMonth(), $ref->copy()->startOfMonth()->subMonth()];
        $since = $months[1]->toDateString();
        $byReversal = $tenant->settings->reversal_month_policy === ReversalMonthPolicy::Reversal;

        $recovered = [];
        foreach ($months as $i => $month) {
            $recovered[$i] = ['label' => self::MONTHS[$month->month - 1].' de '.$month->year, 'total' => 0, 'methods' => []];
        }
        $add = function (string $method, string $month, int $cents) use (&$recovered, $months): void {
            foreach ($months as $i => $m) {
                if ($m->toDateString() === $month) {
                    $label = PaymentMethod::from($method)->getLabel();
                    $recovered[$i]['methods'][$label] = ($recovered[$i]['methods'][$label] ?? 0) + $cents;
                    $recovered[$i]['total'] += $cents;
                }
            }
        };

        foreach (DB::select(
            "select method, date_trunc('month', paid_on)::date as m, sum(applied_cents) as cents from payments
             where tenant_id = ? and status = 'applied' and paid_on >= ? group by 1, 2",
            [$tenant->id, $since],
        ) as $row) {
            $add($row->method, $row->m, (int) $row->cents);
        }
        $monthExpression = $byReversal ? 'r.reversed_on' : 'p.paid_on';
        foreach (DB::select(
            "select p.method, date_trunc('month', $monthExpression)::date as m, sum(r.from_bill_cents) as cents
             from payment_reversals r join payments p on p.id = r.payment_id
             where r.tenant_id = ? and $monthExpression >= ? group by 1, 2",
            [$tenant->id, $since],
        ) as $row) {
            $add($row->method, $row->m, -(int) $row->cents);
        }

        $pending = DB::selectOne("select count(*) as n, coalesce(sum(amount_cents - reversed_cents), 0) as cents from payments where tenant_id = ? and status = 'pending'", [$tenant->id]);

        return [
            'recovered' => $recovered,
            'credit_cents' => (int) DB::table('credits')->where('tenant_id', $tenant->id)->sum('amount_cents'),
            'pending_count' => (int) $pending->n,
            'pending_cents' => (int) $pending->cents,
        ];
    }
}
