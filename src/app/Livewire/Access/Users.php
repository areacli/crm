<?php

namespace App\Livewire\Access;

use App\Access\AccessManager;
use App\Access\AccessRefused;
use App\Enums\Permission;
use App\Livewire\Concerns\Toasts;
use App\Livewire\Concerns\WithTable;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Attributes\Url;
use Livewire\Component;

/**
 * Usuários dos credores em que a pessoa tem "gerenciar usuários": uma linha por vínculo (R36). Criar (com senha temporária),
 * ligar quem já existe em outro credor (R36a), mudar o perfil, alterar o nome, redefinir a senha, desativar, reativar e ver o histórico.
 */
#[Layout('layouts.app')]
#[Title('Usuários')]
final class Users extends Component
{
    use Toasts, WithTable;

    #[Url(as: 'credor')]
    public string $tenant = '';

    /** Qual janela está aberta: new, profile, rename ou history. */
    public ?string $modal = null;

    public bool $showModal = false;

    public ?int $targetId = null;

    public string $tenantId = '';

    public string $email = '';

    public string $name = '';

    public string $profileId = '';

    public function mount(): void
    {
        Gate::authorize('viewAny', Membership::class);
    }

    public function updatedTenant(): void
    {
        $this->resetPage();
    }

    protected function sortable(): array
    {
        return [];
    }

    private function tenantIds(): array
    {
        return Auth::user()->tenantIdsWith(Permission::ManageUsers);
    }

    private function target(): Membership
    {
        $membership = Membership::query()->visibleTo(Auth::user(), Permission::ManageUsers)->with(['user', 'profile', 'tenant'])->findOrFail($this->targetId);
        Gate::authorize('update', $membership);

        return $membership;
    }

    public function open(string $modal, ?int $id = null): void
    {
        $this->reset('email', 'name', 'profileId');
        $this->resetErrorBag();
        $this->modal = $modal;
        $this->targetId = $id;
        if ($modal === 'new') {
            Gate::authorize('create', Membership::class);
            $this->tenantId = count($this->tenantIds()) === 1 ? (string) $this->tenantIds()[0] : '';
        } else {
            $m = $this->target();
            $this->profileId = (string) $m->profile_id;
            $this->name = $m->user->name;
        }
        $this->showModal = true;
    }

    public function addUser(): void
    {
        Gate::authorize('create', Membership::class);
        $this->validate(['tenantId' => ['required'], 'email' => ['required', 'email', 'max:254'], 'profileId' => ['required']], [], ['tenantId' => 'credor', 'email' => 'e-mail', 'profileId' => 'perfil']);
        $actor = Auth::user();
        $tenant = Tenant::findOrFail((int) $this->tenantId);
        $profile = Profile::findOrFail((int) $this->profileId);
        $email = mb_strtolower(trim($this->email));
        $manager = app(AccessManager::class);

        try {
            $existing = User::where('email', $email)->first();
            if ($existing !== null) {
                $manager->linkExisting($actor, $tenant, $existing, $profile);
                $this->toast("{$existing->name} ({$existing->email}) foi ligado(a) a {$tenant->name}", 'success', 'A pessoa recebeu um aviso no sistema.');
            } else {
                if (trim($this->name) === '') {
                    $this->addError('name', 'Informe o nome do novo usuário.');

                    return;
                }
                [$user, $password] = $manager->createUser($actor, $tenant, $email, trim($this->name), $profile);
                $this->toast("Usuário {$user->email} criado", 'success', "Senha temporária (válida por 72 horas; não será mostrada de novo): {$password}", persistent: true);
            }
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->showModal = false;
    }

    public function changeProfile(): void
    {
        $this->validate(['profileId' => ['required']], [], ['profileId' => 'perfil']);
        $this->run(fn () => app(AccessManager::class)->changeProfile(Auth::user(), $this->target(), Profile::findOrFail((int) $this->profileId)), 'Perfil alterado');
    }

    public function rename(): void
    {
        $this->validate(['name' => ['required', 'max:150']], [], ['name' => 'nome']);
        $this->run(fn () => app(AccessManager::class)->rename(Auth::user(), $this->target(), trim($this->name)), 'Nome alterado');
    }

    public function resetPassword(int $id): void
    {
        $this->targetId = $id;
        try {
            $membership = $this->target();
            $password = app(AccessManager::class)->resetPassword(Auth::user(), $membership);
            $this->toast("Senha de {$membership->user->email} redefinida", 'success', "Senha temporária (não será mostrada de novo): {$password}", persistent: true);
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());
        }
    }

    public function setActive(int $id, bool $active): void
    {
        $this->targetId = $id;
        $this->run(fn () => app(AccessManager::class)->setActive(Auth::user(), $this->target(), $active), $active ? 'Acesso reativado' : 'Acesso desativado');
    }

    private function run(callable $change, string $done): void
    {
        try {
            $change();
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->showModal = false;
        $this->toast($done);
    }

    public function render()
    {
        $user = Auth::user();
        $ids = $this->tenantIds();
        $query = Membership::query()->visibleTo($user, Permission::ManageUsers)->with(['user', 'profile', 'tenant'])
            ->when($this->tenant !== '', fn ($q) => $q->where('tenant_id', (int) $this->tenant))
            ->when($this->search !== '', fn ($q) => $q->whereHas('user', fn ($u) => $u->where('name', 'ilike', "%{$this->search}%")->orWhere('email', 'ilike', "%{$this->search}%")))
            ->orderBy('id');

        $target = $this->modal && $this->targetId ? Membership::query()->visibleTo($user, Permission::ManageUsers)->with(['user', 'tenant'])->find($this->targetId) : null;
        $profileTenant = $this->modal === 'new' ? (int) $this->tenantId : $target?->tenant_id;

        return view('livewire.access.users', [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'profiles' => $profileTenant ? Profile::query()->where('tenant_id', $profileTenant)->orderBy('name')->pluck('name', 'id') : collect(),
            'target' => $target,
            'personal' => fn (Membership $m) => app(AccessManager::class)->isPersonalEditable($m),
            'events' => $this->modal === 'history' && $target ? DB::table('access_events')->where('user_id', $target->user_id)
                ->where(fn ($q) => $q->where('tenant_id', $target->tenant_id)->orWhereNull('tenant_id'))->orderByDesc('occurred_at')->orderByDesc('id')->limit(100)->get() : collect(),
            'me' => $user,
        ]);
    }
}
