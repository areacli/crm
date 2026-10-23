<?php

namespace App\Livewire\Access\Profiles;

use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Enums\Permission;
use App\Livewire\Concerns\Toasts;
use App\Livewire\Concerns\WithTable;
use App\Models\Profile;
use App\Models\Tenant;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/** Perfis dos credores em que a pessoa tem "gerenciar perfis" (R30 a R35); perfil com usuários não se apaga. */
#[Layout('layouts.app')]
#[Title('Perfis')]
final class Index extends Component
{
    use Toasts, WithTable;

    #[Url(as: 'credor')]
    public string $tenant = '';

    public function mount(): void
    {
        Gate::authorize('viewAny', Profile::class);
    }

    public function updatedTenant(): void
    {
        $this->resetPage();
    }

    protected function sortable(): array
    {
        return ['name'];
    }

    public function delete(int $id): void
    {
        $profile = Profile::query()->visibleTo(Auth::user(), Permission::ManageProfiles)->findOrFail($id);
        Gate::authorize('delete', $profile);
        try {
            app(ProfileManager::class)->delete(Auth::user(), $profile);
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->toast('Perfil apagado');
    }

    public function render()
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageProfiles);
        $query = Profile::query()->visibleTo(Auth::user(), Permission::ManageProfiles)->with('tenant')->withCount('memberships')
            ->when($this->tenant !== '', fn ($q) => $q->where('tenant_id', (int) $this->tenant))->orderBy('name');

        return view('livewire.access.profiles.index', [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
        ]);
    }
}
