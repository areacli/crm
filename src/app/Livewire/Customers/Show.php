<?php

namespace App\Livewire\Customers;

use App\Access\AccessRefused;
use App\Demo\DemoMode;
use App\Livewire\Concerns\Toasts;
use App\Models\Bill;
use App\Models\Contract;
use App\Models\Customer;
use App\Payments\CreditTransfer;
use App\Support\Money;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Component;

/**
 * Ficha do cliente (R22): dados, situação, títulos por contrato, crédito por contrato, pagos, retirados, o histórico de
 * acionamentos (componente próprio) e a transferência de crédito entre contratos (R55a, permissão 17).
 */
#[Layout('layouts.app')]
final class Show extends Component
{
    use Toasts;

    public Customer $customer;

    public bool $showTransfer = false;

    public ?int $fromContract = null;

    public string $toCode = '';

    public string $amount = '';

    public string $reason = '';

    public function mount(Customer $customer): void
    {
        // Cliente de credor sem acesso responde como "não encontrado", para não revelar que existe (MT-5).
        Gate::authorize('view', $customer);
        $this->customer = $customer;
    }

    public function title(): string
    {
        return $this->customer->name;
    }

    /** @return list<int> contratos em que o cliente tem título */
    private function contractIds(): array
    {
        return Bill::query()->where('customer_id', $this->customer->id)->pluck('contract_id')->unique()->values()->all();
    }

    /** Contratos do cliente com crédito a transferir. */
    public function creditContracts()
    {
        return Contract::query()->whereIn('id', $this->contractIds())->get()->filter(fn (Contract $c) => $c->creditCents() > 0)->values();
    }

    public function canTransfer(): bool
    {
        return Gate::allows('transferCredit', $this->customer) && $this->creditContracts()->isNotEmpty();
    }

    public function openTransfer(): void
    {
        Gate::authorize('transferCredit', $this->customer);
        $this->reset('toCode', 'amount', 'reason');
        $this->fromContract = $this->creditContracts()->first()?->id;
        $this->resetErrorBag();
        $this->showTransfer = true;
    }

    /** R55a: transferir crédito entre contratos do mesmo credor. */
    public function transfer(): void
    {
        Gate::authorize('transferCredit', $this->customer);
        $this->validate([
            'fromContract' => ['required', 'integer'],
            'toCode' => ['required', 'string', 'max:100'],
            'amount' => ['required', 'string'],
            'reason' => ['required', 'string', 'max:300'],
        ], [], ['fromContract' => 'contrato de origem', 'toCode' => 'contrato de destino', 'amount' => 'valor', 'reason' => 'motivo']);

        [$cents, $problem] = Money::parseCents($this->amount);
        $to = Contract::query()->where('tenant_id', $this->customer->tenant_id)->where('code', trim($this->toCode))->first();
        $from = Contract::query()->whereIn('id', $this->contractIds())->find($this->fromContract);
        try {
            if ($cents === null) {
                throw new AccessRefused((string) $problem);
            }
            if ($to === null || $from === null) {
                throw new AccessRefused('Contrato de destino não encontrado neste credor.');
            }
            // Na demonstração, o texto livre do visitante não fica gravado.
            $reason = DemoMode::enabled() ? 'motivo descartado na demonstração' : $this->reason;
            app(CreditTransfer::class)->transfer(Auth::user(), $from, $to, $cents, $reason);
        } catch (AccessRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->showTransfer = false;
        $this->toast('Crédito transferido');
    }

    public function render()
    {
        return view('livewire.customers.show', ['customer' => $this->customer->load('tenant.settings')])->title($this->customer->name);
    }
}
