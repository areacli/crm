<?php

namespace App\Portfolio;

use App\Enums\Permission;
use App\Enums\UpcomingDisplay;
use App\Models\Customer;
use App\Models\Tenant;
use App\Models\TenantSettings;
use App\Models\User;
use App\Support\Text;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Carbon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\DB;

/**
 * Consultas da carteira (R17 a R23), sempre limitadas aos credores em que o usuário pode consultar a carteira
 * (MT-5). Situação vencido ou a vencer e dias de atraso são calculados na consulta com a data de referência;
 * nada disso é gravado (R6, R17).
 */
final class PortfolioQuery
{
    private readonly string $reference;

    public function __construct(private readonly User $user, ?Carbon $reference = null)
    {
        $this->reference = ($reference ?? now())->toDateString();
    }

    /** @return list<int> */
    public function tenantIds(): array
    {
        return $this->user->tenantIdsWith(Permission::ViewPortfolio);
    }

    /**
     * Lista de clientes (R21): valores, maior atraso e faixa. Sem busca, só quem tem título em cobrança
     * (no modo "só na ficha", só quem tem título vencido); com busca, qualquer cliente do credor.
     *
     * @param  ?int  $bracket  índice da faixa pedida, ou -1 para "sem atraso"
     */
    public function customers(?string $search = null, ?int $bracket = null): Builder
    {
        $ids = $this->tenantIds();
        $ref = $this->reference;

        $aggregate = DB::table('bills')
            ->selectRaw('customer_id')
            ->selectRaw('count(*) as bills_count')
            ->selectRaw('coalesce(sum(amount_cents - paid_cents) filter (where due_date < ?), 0) as overdue_cents', [$ref])
            ->selectRaw('coalesce(sum(amount_cents - paid_cents) filter (where due_date >= ?), 0) as upcoming_cents', [$ref])
            ->selectRaw('max(?::date - due_date) filter (where due_date < ?) as max_days_overdue', [$ref, $ref])
            ->where('status', 'active')
            ->whereIn('tenant_id', $ids ?: [0])
            ->groupBy('customer_id');

        $query = Customer::query()
            ->from('customers')
            ->leftJoinSub($aggregate, 'agg', 'agg.customer_id', '=', 'customers.id')
            ->select('customers.*')
            ->selectRaw('coalesce(agg.bills_count, 0) as bills_count')
            ->selectRaw('coalesce(agg.overdue_cents, 0) as overdue_cents')
            ->selectRaw('coalesce(agg.upcoming_cents, 0) as upcoming_cents')
            ->selectRaw('agg.max_days_overdue')
            ->visibleTo($this->user, Permission::ViewPortfolio);

        if ($search !== null && trim($search) !== '') {
            $term = Text::fold($search);
            $digits = preg_replace('/\D/', '', $search);
            $query->where(function (Builder $q) use ($term, $digits) {
                $q->whereRaw("translate(lower(customers.name), 'áàâãäéèêëíìîïóòôõöúùûüç', 'aaaaaeeeeiiiiooooouuuuc') like ?", ['%'.$term.'%']);
                if ($digits !== '') {
                    $q->orWhere('customers.document', 'like', $digits.'%');
                }
            });
        } else {
            $this->restrictToCollection($query, $ids);
        }

        if ($bracket !== null) {
            $this->restrictToBracket($query, $ids, $bracket);
        }

        return $query->orderByDesc('overdue_cents')->orderBy('customers.name');
    }

    /** Sem busca a lista mostra só quem está em cobrança; no modo "só na ficha", quem tem título vencido (R20, R21). */
    private function restrictToCollection(Builder $query, array $ids): void
    {
        $detailOnly = $this->settingsByTenant($ids)->filter(fn (TenantSettings $s) => $s->upcoming_display === UpcomingDisplay::DetailOnly)->keys()->all();

        $query->where(function (Builder $q) use ($detailOnly) {
            $q->where(function (Builder $q) use ($detailOnly) {
                $q->whereRaw('coalesce(agg.bills_count, 0) > 0');
                if ($detailOnly !== []) {
                    $q->where(function (Builder $q) use ($detailOnly) {
                        $q->whereNotIn('customers.tenant_id', $detailOnly)->orWhereRaw('coalesce(agg.overdue_cents, 0) > 0');
                    });
                }
            });
        });
    }

    /** Cada credor usa as próprias faixas (MT-7): a condição é montada por credor. */
    private function restrictToBracket(Builder $query, array $ids, int $bracket): void
    {
        $settings = $this->settingsByTenant($ids);

        $query->where(function (Builder $q) use ($settings, $bracket) {
            foreach ($settings as $tenantId => $s) {
                $tenantId = (int) $tenantId;
                $brackets = AgingBrackets::fromStored($s->aging_brackets);
                if ($bracket === -1) {
                    $q->orWhereRaw('(customers.tenant_id = ? and agg.max_days_overdue is null)', [$tenantId]);
                } elseif (isset($brackets->brackets[$bracket])) {
                    $q->orWhereRaw('(customers.tenant_id = ? and '.$brackets->sqlIndex('agg.max_days_overdue').' = ?)', [$tenantId, (int) $bracket]);
                }
            }
            $q->orWhereRaw('false');
        });
    }

    /** @return Collection<int, TenantSettings> */
    public function settingsByTenant(?array $ids = null)
    {
        return TenantSettings::query()->whereIn('tenant_id', $ids ?? $this->tenantIds())->get()->keyBy('tenant_id');
    }

    /** Faixa do cliente: a do título vencido mais atrasado (R19); null quando não há título vencido ("sem atraso"). */
    public function bracketLabel(Tenant|int $tenant, ?int $maxDaysOverdue): string
    {
        if ($maxDaysOverdue === null || $maxDaysOverdue < 1) {
            return 'sem atraso';
        }
        $tenantId = $tenant instanceof Tenant ? $tenant->id : $tenant;
        $brackets = AgingBrackets::fromStored($this->settingsByTenant()[$tenantId]->aging_brackets);

        return $brackets->label($brackets->indexFor($maxDaysOverdue));
    }

    public function referenceDate(): string
    {
        return $this->reference;
    }
}
