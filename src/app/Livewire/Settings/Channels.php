<?php

namespace App\Livewire\Settings;

use App\Enums\ChannelType;
use App\Enums\Permission;
use App\Livewire\Concerns\Toasts;
use App\Livewire\Concerns\WithTable;
use App\Models\Change;
use App\Models\PaymentChannel;
use App\Models\Tenant;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Illuminate\Validation\Rule;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/**
 * Configuração, aba "Canais de recebimento" (R45): conta, convênio ou estabelecimento de cartão do credor. O código só muda
 * enquanto o canal não tem pagamento; canal com pagamento só é desativado; tudo fica registrado (quem, quando, antes, depois).
 */
#[Layout('layouts.app')]
#[Title('Canais de recebimento')]
final class Channels extends Component
{
    use Toasts, WithTable;

    public bool $showForm = false;

    public ?int $editingId = null;

    public string $tenantId = '';

    public string $type = 'account';

    public string $code = '';

    public string $description = '';

    public bool $active = true;

    public function mount(): void
    {
        Gate::authorize('viewAny', PaymentChannel::class);
    }

    protected function sortable(): array
    {
        return ['code', 'description'];
    }

    private function tenantIds(): array
    {
        return Auth::user()->tenantIdsWith(Permission::ChangeSettings);
    }

    public function openCreate(): void
    {
        Gate::authorize('create', PaymentChannel::class);
        $this->reset('editingId', 'code', 'description');
        $this->type = 'account';
        $this->active = true;
        $this->tenantId = count($this->tenantIds()) === 1 ? (string) $this->tenantIds()[0] : '';
        $this->resetErrorBag();
        $this->showForm = true;
    }

    public function openEdit(int $id): void
    {
        $channel = PaymentChannel::query()->visibleTo(Auth::user(), Permission::ChangeSettings)->findOrFail($id);
        Gate::authorize('update', $channel);
        $this->editingId = $channel->id;
        $this->tenantId = (string) $channel->tenant_id;
        $this->type = $channel->type->value;
        $this->code = $channel->code;
        $this->description = $channel->description;
        $this->active = $channel->active;
        $this->resetErrorBag();
        $this->showForm = true;
    }

    public function hasPayments(): bool
    {
        return $this->editingId !== null && PaymentChannel::query()->find($this->editingId)?->payments()->exists();
    }

    public function save(): void
    {
        $channel = $this->editingId ? PaymentChannel::query()->visibleTo(Auth::user(), Permission::ChangeSettings)->findOrFail($this->editingId) : null;
        $channel ? Gate::authorize('update', $channel) : Gate::authorize('create', PaymentChannel::class);

        $tenantId = $channel?->tenant_id ?? (int) $this->tenantId;
        abort_unless(in_array($tenantId, $this->tenantIds(), true), 403);
        $this->validate([
            'type' => ['required', Rule::enum(ChannelType::class)],
            'code' => ['required', 'max:100', Rule::unique('payment_channels', 'code')->where('tenant_id', $tenantId)->ignore($channel?->id)],
            'description' => ['required', 'max:200'],
        ], [], ['type' => 'tipo', 'code' => 'código', 'description' => 'descrição']);

        $data = ['type' => $this->type, 'description' => $this->description, 'active' => $this->active];
        // O código é o que a planilha de pagamentos traz: só muda enquanto o canal não tem pagamento (R45).
        if ($channel === null || ! $channel->payments()->exists()) {
            $data['code'] = $this->code;
        }

        if ($channel === null) {
            $channel = PaymentChannel::create($data + ['tenant_id' => $tenantId]);
            $this->log($channel, 'created', 'code', null, $channel->code);
        } else {
            $channel->fill($data);
            foreach ($channel->getDirty() as $field => $after) {
                $this->log($channel, 'updated', $field, (string) $channel->getOriginal($field), (string) $after);
            }
            $channel->save();
        }
        $this->showForm = false;
        $this->toast('Canal salvo');
    }

    /** R45 (revisão 7): só o canal sem pagamento pode ser apagado. */
    public function delete(int $id): void
    {
        $channel = PaymentChannel::query()->visibleTo(Auth::user(), Permission::ChangeSettings)->findOrFail($id);
        if (Gate::denies('delete', $channel)) {
            $this->toastError('O canal tem pagamentos: só pode ser desativado.');

            return;
        }
        $this->log($channel, 'deleted', 'code', $channel->code, null);
        $channel->delete();
        $this->toast('Canal apagado');
    }

    private function log(PaymentChannel $channel, string $event, string $field, ?string $before, ?string $after): void
    {
        Change::create([
            'tenant_id' => $channel->tenant_id, 'user_id' => Auth::id(), 'subject_type' => 'channel', 'subject_id' => $channel->id,
            'event' => $event, 'field' => $field, 'before' => $before, 'after' => $after, 'occurred_at' => now(),
        ]);
    }

    public function render()
    {
        $ids = $this->tenantIds();
        $query = PaymentChannel::query()->visibleTo(Auth::user(), Permission::ChangeSettings)->with('tenant')->withCount('payments')
            ->when($this->search !== '', fn ($q) => $q->where(fn ($w) => $w->where('code', 'ilike', "%{$this->search}%")->orWhere('description', 'ilike', "%{$this->search}%")))
            ->orderBy('code');

        return view('livewire.settings.channels', [
            'rows' => $this->paginateTable($query),
            'several' => count($ids) > 1,
            'tenants' => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id'),
            'types' => ChannelType::cases(),
        ]);
    }
}
