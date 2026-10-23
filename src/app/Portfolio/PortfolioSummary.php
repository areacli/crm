<?php

namespace App\Portfolio;

use App\Enums\ContactResultType;
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
        ] + $this->payments($tenant) + ['contacts' => $this->contacts($tenant)];
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

    /**
     * Acionamentos dos últimos 7 e 30 dias, pela data do contato e sem anulados (R79): número de acionamentos e de clientes
     * acionados, no total e por tipo de resultado. Um cliente acionado mais de uma vez conta uma vez em cada tipo.
     *
     * Duas passadas na tabela, as duas agrupando por cliente (nada de `count(distinct)`, que ordena todas as linhas do período
     * e vai a disco com volume grande): uma por tipo e cliente, outra só por cliente. Cada passada traz os dois períodos.
     *
     * @return array<int, array{total: array{attempts: int, customers: int}, types: array<string, array{attempts: int, customers: int}>}>
     */
    private function contacts(Tenant $tenant): array
    {
        $since7 = Carbon::parse($this->reference)->subDays(7)->startOfDay();
        $since30 = Carbon::parse($this->reference)->subDays(30)->startOfDay();
        $out = [7 => ['total' => ['attempts' => 0, 'customers' => 0], 'types' => []], 30 => ['total' => ['attempts' => 0, 'customers' => 0], 'types' => []]];
        foreach ([7, 30] as $days) {
            foreach (ContactResultType::cases() as $type) {
                $out[$days]['types'][$type->value] = ['attempts' => 0, 'customers' => 0];
            }
        }

        $byType = DB::select(<<<'SQL'
            select result_type, count(*) as customers30, count(*) filter (where n7 > 0) as customers7, sum(n30) as attempts30, sum(n7) as attempts7
            from (select result_type, customer_id, count(*) as n30, count(*) filter (where contacted_at >= ?) as n7
                  from contact_attempts where tenant_id = ? and voided_at is null and contacted_at >= ? group by result_type, customer_id) g
            group by result_type
        SQL, [$since7, $tenant->id, $since30]);
        foreach ($byType as $row) {
            $out[7]['types'][$row->result_type] = ['attempts' => (int) $row->attempts7, 'customers' => (int) $row->customers7];
            $out[30]['types'][$row->result_type] = ['attempts' => (int) $row->attempts30, 'customers' => (int) $row->customers30];
        }

        $total = DB::selectOne(<<<'SQL'
            select count(*) as customers30, count(*) filter (where n7 > 0) as customers7, coalesce(sum(n30), 0) as attempts30, coalesce(sum(n7), 0) as attempts7
            from (select customer_id, count(*) as n30, count(*) filter (where contacted_at >= ?) as n7
                  from contact_attempts where tenant_id = ? and voided_at is null and contacted_at >= ? group by customer_id) g
        SQL, [$since7, $tenant->id, $since30]);
        $out[7]['total'] = ['attempts' => (int) $total->attempts7, 'customers' => (int) $total->customers7];
        $out[30]['total'] = ['attempts' => (int) $total->attempts30, 'customers' => (int) $total->customers30];

        return $out;
    }
}
