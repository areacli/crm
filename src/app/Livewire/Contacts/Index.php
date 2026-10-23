<?php

namespace App\Livewire\Contacts;

use App\Enums\ContactChannel;
use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Livewire\Concerns\WithTable;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Lista de acionamentos dos credores em que o usuário consulta a carteira (R78): período (padrão, os últimos 7 dias; no máximo
 * 92 por consulta), operador, canal, resultado, tipo e credor; os anulados ficam fora, salvo se pedidos.
 */
#[Layout('layouts.app')]
#[Title('Acionamentos')]
final class Index extends Component
{
    use WithTable;

    private const int MAX_PERIOD_DAYS = 92;

    #[Url(as: 'de')]
    public string $from = '';

    #[Url(as: 'ate')]
    public string $until = '';

    #[Url(as: 'operador')]
    public string $operator = '';

    #[Url(as: 'canal')]
    public string $channel = '';

    #[Url(as: 'resultado')]
    public string $result = '';

    #[Url(as: 'tipo')]
    public string $type = '';

    #[Url(as: 'credor')]
    public string $tenant = '';

    #[Url(as: 'anulados')]
    public bool $includeVoided = false;

    public function mount(): void
    {
        Gate::authorize('viewAny', ContactAttempt::class);
        $this->from = $this->from ?: now()->subDays(7)->toDateString();
        $this->until = $this->until ?: now()->toDateString();
    }

    protected function sortable(): array
    {
        return ['contacted_at'];
    }

    public function updated(string $name): void
    {
        if (in_array($name, ['from', 'until', 'operator', 'channel', 'result', 'type', 'tenant', 'includeVoided'], true)) {
            $this->resetPage();
        }
    }

    public function render()
    {
        $user = Auth::user();
        $ids = $user->tenantIdsWith(Permission::ViewPortfolio);

        $until = Carbon::parse($this->until ?: now())->endOfDay();
        $from = Carbon::parse($this->from ?: $until->copy()->subDays(7))->startOfDay();
        if ($from->diffInDays($until) > self::MAX_PERIOD_DAYS) {
            $from = $until->copy()->subDays(self::MAX_PERIOD_DAYS)->startOfDay();
        }

        $query = ContactAttempt::query()->visibleTo($user, Permission::ViewPortfolio)
            ->with(['customer', 'contract', 'result', 'user', 'tenant'])
            ->whereBetween('contacted_at', [$from, $until])
            ->when(! $this->includeVoided, fn ($q) => $q->whereNull('voided_at'))
            ->when($this->operator !== '', fn ($q) => $q->where('user_id', (int) $this->operator))
            ->when($this->channel !== '', fn ($q) => $q->where('channel', $this->channel))
            ->when($this->result !== '', fn ($q) => $q->where('result_id', (int) $this->result))
            ->when($this->type !== '', fn ($q) => $q->where('result_type', $this->type))
            ->when($this->tenant !== '', fn ($q) => $q->where('tenant_id', (int) $this->tenant))
            ->orderByDesc('contacted_at')->orderByDesc('id');

        return view('livewire.contacts.index', [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'operators' => User::query()->whereHas('memberships', fn ($q) => $q->whereIn('tenant_id', $ids ?: [0]))->orderBy('name')->pluck('name', 'id'),
            'results' => ContactResult::query()->whereIn('tenant_id', $ids ?: [0])->with('tenant')->orderBy('name')->get()
                ->mapWithKeys(fn (ContactResult $r) => [$r->id => count($ids) > 1 ? $r->name.' ('.$r->tenant->name.')' : $r->name]),
            'channels' => ContactChannel::cases(),
            'types' => ContactResultType::cases(),
        ]);
    }
}
