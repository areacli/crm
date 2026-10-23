<?php

namespace App\Livewire\Customers;

use App\Enums\Permission;
use App\Enums\UpcomingDisplay;
use App\Livewire\Concerns\WithTable;
use App\Models\Customer;
use App\Models\Tenant;
use App\Portfolio\AgingBrackets;
use App\Portfolio\PortfolioQuery;
use App\Support\Money;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Lista de clientes (R21): valores, maior atraso e faixa de cada cliente dos credores em que o usuário consulta a carteira.
 * Sem busca, só quem tem título em cobrança; com busca (sem acento, por nome ou documento), qualquer cliente do credor.
 */
#[Layout('layouts.app')]
#[Title('Clientes')]
final class Index extends Component
{
    use WithTable;

    #[Url(as: 'faixa')]
    public string $bracket = '';

    #[Url(as: 'credor')]
    public string $tenant = '';

    public function mount(): void
    {
        Gate::authorize('viewAny', Customer::class);
    }

    public function updatedBracket(): void
    {
        $this->resetPage();
    }

    public function updatedTenant(): void
    {
        $this->resetPage();
    }

    protected function sortable(): array
    {
        return ['name', 'bills_count', 'overdue_cents', 'upcoming_cents', 'max_days_overdue'];
    }

    public function render()
    {
        $user = Auth::user();
        $portfolio = new PortfolioQuery($user);
        $ids = $user->tenantIdsWith(Permission::ViewPortfolio);

        $query = $portfolio->customers($this->search !== '' ? $this->search : null, $this->bracket === '' ? null : (int) $this->bracket)->with('tenant');
        if ($this->tenant !== '' && in_array((int) $this->tenant, $ids, true)) {
            $query->where('customers.tenant_id', (int) $this->tenant);
        }

        $settings = $portfolio->settingsByTenant();
        $first = $settings->first();
        $brackets = ['-1' => 'Sem atraso'];
        if ($first !== null) {
            foreach (AgingBrackets::fromStored($first->aging_brackets)->labels() as $i => $label) {
                $brackets[(string) $i] = $label;
            }
        }

        return view('livewire.customers.index', [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => count($ids) > 1 ? Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all() : [],
            'brackets' => $brackets,
            'portfolio' => $portfolio,
            'settings' => $settings,
        ]);
    }

    public function upcomingText(Customer $row, $settings): string
    {
        $mode = $settings[$row->tenant_id]->upcoming_display;

        return $mode === UpcomingDisplay::DetailOnly ? '—' : 'R$ '.Money::format((int) $row->upcoming_cents);
    }
}
