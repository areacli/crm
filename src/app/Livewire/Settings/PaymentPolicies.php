<?php

namespace App\Livewire\Settings;

use App\Enums\PartialPaymentPolicy;
use App\Enums\Permission;
use App\Enums\ReversalMonthPolicy;
use App\Enums\WithdrawnPaymentPolicy;
use App\Enums\WithdrawnReversalPolicy;
use App\Livewire\Concerns\Toasts;
use App\Models\Change;
use App\Models\Tenant;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/** Configuração, aba "Políticas de pagamento": pagamento menor que o saldo, título retirado, estorno e mês do estorno (R46, R46a, R62a, R64; permissão 14). */
#[Layout('layouts.app')]
#[Title('Políticas de pagamento')]
final class PaymentPolicies extends Component
{
    use Toasts;

    private const array FIELDS = [
        'partial_payment_policy' => PartialPaymentPolicy::class,
        'withdrawn_payment_policy' => WithdrawnPaymentPolicy::class,
        'withdrawn_reversal_policy' => WithdrawnReversalPolicy::class,
        'reversal_month_policy' => ReversalMonthPolicy::class,
    ];

    public string $tenantId = '';

    public string $partial_payment_policy = '';

    public string $withdrawn_payment_policy = '';

    public string $withdrawn_reversal_policy = '';

    public string $reversal_month_policy = '';

    public function mount(): void
    {
        Gate::authorize('configurePayments', Tenant::class);
        $this->tenantId = (string) $this->tenants()->first()->id;
        $this->load();
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->with('settings')->whereIn('id', Auth::user()->tenantIdsWith(Permission::ChangeFinancialPolicies) ?: [0])->orderBy('name')->get();
    }

    public function updatedTenantId(): void
    {
        $this->load();
    }

    private function load(): void
    {
        $settings = $this->tenants()->firstWhere('id', (int) $this->tenantId)?->settings;
        abort_if($settings === null, 404);
        foreach (array_keys(self::FIELDS) as $field) {
            $this->{$field} = $settings->{$field}->value;
        }
    }

    public function save(): void
    {
        $tenant = Tenant::findOrFail((int) $this->tenantId);
        Gate::authorize('updatePaymentPolicies', $tenant);

        $settings = $tenant->settings;
        foreach (self::FIELDS as $field => $enum) {
            $new = $enum::from($this->{$field});
            $before = $settings->{$field}->value;
            if ($before !== $new->value) {
                $settings->{$field} = $new;
                // Cada mudança de política fica registrada: quem, quando, antes e depois (PD4).
                Change::create([
                    'tenant_id' => $tenant->id, 'user_id' => Auth::id(), 'subject_type' => 'settings', 'subject_id' => $tenant->id,
                    'event' => $field.'_changed', 'field' => $field, 'before' => $before, 'after' => $new->value, 'occurred_at' => now(),
                ]);
            }
        }
        $settings->save();

        $this->toast('Políticas salvas');
    }

    public function render()
    {
        $options = fn (string $enum) => collect($enum::cases())->mapWithKeys(fn ($c) => [$c->value => $c->getLabel()])->all();

        return view('livewire.settings.payment-policies', [
            'tenants' => $this->tenants(),
            'groups' => [
                'partial_payment_policy' => ['Pagamento menor que o saldo', $options(PartialPaymentPolicy::class)],
                'withdrawn_payment_policy' => ['Pagamento de título retirado', $options(WithdrawnPaymentPolicy::class)],
                'withdrawn_reversal_policy' => ['Título retirado, quitado e depois estornado', $options(WithdrawnReversalPolicy::class)],
                'reversal_month_policy' => ['Mês em que o estorno desconta do valor recuperado', $options(ReversalMonthPolicy::class)],
            ],
        ]);
    }
}
