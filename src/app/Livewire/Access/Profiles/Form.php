<?php

namespace App\Livewire\Access\Profiles;

use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Enums\Permission;
use App\Livewire\Concerns\Toasts;
use App\Models\Profile;
use App\Models\Tenant;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Criar ou editar um perfil: nome e as 17 permissões (R30 a R35, PD6, PD7, AC7, R41). */
#[Layout('layouts.app')]
final class Form extends Component
{
    use Toasts;

    public ?Profile $profile = null;

    public string $tenantId = '';

    public string $name = '';

    /** @var list<string> */
    public array $permissions = [];

    public function mount(?Profile $profile = null): void
    {
        if ($profile?->exists) {
            Gate::authorize('update', $profile);
            $this->profile = $profile;
            $this->tenantId = (string) $profile->tenant_id;
            $this->name = $profile->name;
            $this->permissions = $profile->permissions ?? [];
        } else {
            Gate::authorize('create', Profile::class);
            $ids = Auth::user()->tenantIdsWith(Permission::ManageProfiles);
            $this->tenantId = count($ids) === 1 ? (string) $ids[0] : '';
        }
    }

    public function save()
    {
        $this->validate(['tenantId' => ['required'], 'name' => ['required', 'max:60'], 'permissions' => ['required', 'array', 'min:1']], [], ['tenantId' => 'credor', 'name' => 'nome do perfil', 'permissions' => 'permissões']);
        $manager = app(ProfileManager::class);
        try {
            if ($this->profile) {
                $manager->update(Auth::user(), $this->profile, $this->name, $this->permissions);
            } else {
                $manager->create(Auth::user(), Tenant::findOrFail((int) $this->tenantId), $this->name, $this->permissions);
            }
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());

            return null;
        }
        session()->flash('status', 'Perfil salvo');

        return $this->redirectRoute('profiles.index', navigate: true);
    }

    public function render()
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageProfiles);

        return view('livewire.access.profiles.form', [
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'all' => Permission::cases(),
        ])->title($this->profile ? 'Editar perfil' : 'Novo perfil');
    }
}
