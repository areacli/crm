<?php

namespace App\Livewire\Settings;

use App\Enums\Permission;
use App\Enums\UpcomingDisplay;
use App\Livewire\Concerns\Toasts;
use App\Models\Tenant;
use App\Portfolio\InvalidBrackets;
use App\Portfolio\SettingsService;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/** Configuração, aba "Políticas da carteira": faixas de atraso (R18) e tratamento dos títulos a vencer (R20). */
#[Layout('layouts.app')]
#[Title('Políticas da carteira')]
final class Portfolio extends Component
{
    use Toasts;

    public string $tenantId = '';

    /** @var list<array{from: mixed, to: mixed}> */
    public array $brackets = [];

    public string $upcoming = 'separate';

    public function mount(): void
    {
        Gate::authorize('configure', Tenant::class);
        $this->tenantId = (string) $this->tenants()->first()->id;
        $this->load();
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->with('settings')->whereIn('id', Auth::user()->tenantIdsWith(Permission::ChangeSettings) ?: [0])->orderBy('name')->get();
    }

    public function updatedTenantId(): void
    {
        $this->load();
    }

    private function load(): void
    {
        $settings = $this->tenants()->firstWhere('id', (int) $this->tenantId)?->settings;
        abort_if($settings === null, 404);
        $this->brackets = array_map(fn ($b) => ['from' => $b['from'], 'to' => $b['to']], $settings->aging_brackets);
        $this->upcoming = $settings->upcoming_display->value;
    }

    public function addBracket(): void
    {
        $last = end($this->brackets);
        $this->brackets[] = ['from' => is_numeric($last['to'] ?? null) ? $last['to'] + 1 : '', 'to' => ''];
    }

    public function removeBracket(int $index): void
    {
        unset($this->brackets[$index]);
        $this->brackets = array_values($this->brackets);
    }

    public function save(): void
    {
        $tenant = Tenant::findOrFail((int) $this->tenantId);
        Gate::authorize('updateSettings', $tenant);

        $service = app(SettingsService::class);
        try {
            $service->updateBrackets($tenant, array_values($this->brackets), Auth::user());
        } catch (InvalidBrackets $e) {
            // As faixas anteriores continuam valendo (R18).
            $this->toast('Faixas não salvas', 'danger', ucfirst($e->getMessage()).'. As faixas anteriores continuam valendo.');

            return;
        }
        $service->updateUpcomingDisplay($tenant, UpcomingDisplay::from($this->upcoming), Auth::user());
        $this->toast('Configuração salva');
    }

    public function render()
    {
        return view('livewire.settings.portfolio', ['tenants' => $this->tenants()]);
    }
}
