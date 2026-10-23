<?php

namespace App\Livewire\Imports;

use App\Enums\Permission;
use App\Livewire\Concerns\WithTable;
use App\Models\Import;
use App\Models\Tenant;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Url;
use Livewire\Component;

/** Importações de carteira: histórico, andamento e resultado (R10). A lista de pagamentos (`Payments\Index`) herda esta. */
#[Layout('layouts.app')]
class Index extends Component
{
    use WithTable;

    #[Url(as: 'credor')]
    public string $tenant = '';

    /** @var list<string> tipos de importação que a lista mostra */
    protected array $kinds = ['portfolio'];

    protected string $title = 'Importações de carteira';

    /** @return list<Permission> permissões que dão acesso à lista */
    protected function permissions(): array
    {
        return [Permission::UploadImports, Permission::ConfirmImports];
    }

    protected function newRoute(): string
    {
        return 'imports.create';
    }

    protected function showRoute(): string
    {
        return 'imports.show';
    }

    protected function view(): string
    {
        return 'livewire.imports.index';
    }

    public function mount(): void
    {
        Gate::authorize('viewAny', Import::class);
        abort_unless(collect($this->permissions())->contains(fn (Permission $p) => Auth::user()->hasAnyPermission($p)), 403);
    }

    public function updatedTenant(): void
    {
        $this->resetPage();
    }

    protected function sortable(): array
    {
        return ['id', 'created_at'];
    }

    public function render()
    {
        $user = Auth::user();
        $ids = array_values(array_unique(array_merge(...array_map(fn (Permission $p) => $user->tenantIdsWith($p), $this->permissions()))));
        $query = Import::query()->visibleTo($user, ...$this->permissions())->whereIn('kind', $this->kinds)->with(['tenant', 'user'])
            ->when($this->tenant !== '', fn ($q) => $q->where('tenant_id', (int) $this->tenant))->orderByDesc('id');

        return view($this->view(), [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'newRoute' => $this->newRoute(),
            'showRoute' => $this->showRoute(),
            'heading' => $this->title,
            'canCreate' => Gate::allows($this->kinds === ['portfolio'] ? 'create' : 'createPayments', Import::class),
        ])->title($this->title);
    }
}
