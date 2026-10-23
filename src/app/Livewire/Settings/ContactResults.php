<?php

namespace App\Livewire\Settings;

use App\Contacts\ContactRefused;
use App\Contacts\ContactResultManager;
use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Livewire\Concerns\Toasts;
use App\Models\ContactResult;
use App\Models\Tenant;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/** Configuração, aba "Resultados de acionamento" (R66, R67): lista do credor, com a permissão "gerenciar resultados". */
#[Layout('layouts.app')]
#[Title('Resultados de acionamento')]
final class ContactResults extends Component
{
    use Toasts;

    #[Url(as: 'credor')]
    public string $tenant = '';

    public bool $showForm = false;

    public ?int $editingId = null;

    public string $tenantId = '';

    public string $name = '';

    public string $type = 'no_contact';

    public string $returnRule = 'allowed';

    public function mount(): void
    {
        Gate::authorize('viewAny', ContactResult::class);
        $ids = $this->tenantIds();
        if ($this->tenant === '' || ! in_array((int) $this->tenant, $ids, true)) {
            $this->tenant = (string) ($ids[0] ?? '');
        }
    }

    private function tenantIds(): array
    {
        return Auth::user()->tenantIdsWith(Permission::ManageContactResults);
    }

    public function openCreate(): void
    {
        Gate::authorize('create', ContactResult::class);
        $this->reset('editingId', 'name');
        $this->type = 'no_contact';
        $this->returnRule = 'allowed';
        $this->tenantId = $this->tenant;
        $this->resetErrorBag();
        $this->showForm = true;
    }

    public function openEdit(int $id): void
    {
        $result = $this->find($id);
        $this->editingId = $result->id;
        $this->tenantId = (string) $result->tenant_id;
        $this->name = $result->name;
        $this->type = $result->type->value;
        $this->returnRule = $result->return_rule->value;
        $this->resetErrorBag();
        $this->showForm = true;
    }

    private function find(int $id): ContactResult
    {
        $result = ContactResult::query()->visibleTo(Auth::user(), Permission::ManageContactResults)->findOrFail($id);
        Gate::authorize('update', $result);

        return $result;
    }

    public function save(): void
    {
        $this->validate(['name' => ['required', 'max:100'], 'type' => ['required'], 'returnRule' => ['required']], [], ['name' => 'nome', 'type' => 'tipo', 'returnRule' => 'regra de retorno']);
        $manager = app(ContactResultManager::class);
        try {
            if ($this->editingId) {
                $manager->update(Auth::user(), $this->find($this->editingId), $this->name, ReturnRule::from($this->returnRule));
            } else {
                $manager->create(Auth::user(), Tenant::findOrFail((int) $this->tenantId), $this->name, ContactResultType::from($this->type), ReturnRule::from($this->returnRule));
            }
        } catch (ContactRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->showForm = false;
        $this->toast('Resultado salvo');
    }

    public function move(int $id, int $direction): void
    {
        $this->run(fn () => app(ContactResultManager::class)->move(Auth::user(), $this->find($id), $direction));
    }

    public function setActive(int $id, bool $active): void
    {
        $this->run(fn () => app(ContactResultManager::class)->setActive(Auth::user(), $this->find($id), $active), $active ? 'Resultado reativado' : 'Resultado desativado');
    }

    private function run(callable $change, ?string $done = null): void
    {
        try {
            $change();
            if ($done) {
                $this->toast($done);
            }
        } catch (ContactRefused $e) {
            $this->toastError($e->getMessage());
        }
    }

    public function render()
    {
        $ids = $this->tenantIds();

        return view('livewire.settings.contact-results', [
            'rows' => ContactResult::query()->visibleTo(Auth::user(), Permission::ManageContactResults)->where('tenant_id', (int) $this->tenant)->withCount('attempts')->orderBy('position')->get(),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'types' => ContactResultType::cases(),
            'rules' => ReturnRule::cases(),
        ]);
    }
}
