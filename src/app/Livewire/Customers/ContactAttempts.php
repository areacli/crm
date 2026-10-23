<?php

namespace App\Livewire\Customers;

use App\Contacts\ContactAttemptService;
use App\Contacts\ContactRefused;
use App\Demo\DemoMode;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Livewire\Concerns\Toasts;
use App\Livewire\Concerns\WithTable;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Contract;
use App\Models\Customer;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;

/**
 * Acionamentos de um cliente na ficha (R69 a R75): histórico do mais recente ao mais antigo, 20 por vez, o formulário de
 * registro e a anulação com motivo. As regras são do `ContactAttemptService`; este componente só monta a tela.
 */
final class ContactAttempts extends Component
{
    use Toasts, WithTable;

    public int $customerId;

    public bool $showRecord = false;

    public string $channel = '';

    public string $resultId = '';

    public string $contractId = '';

    public string $contactUsed = '';

    public string $contactedAt = '';

    public string $returnAt = '';

    public string $text = '';

    public ?int $voidingId = null;

    public string $voidReason = '';

    private function customer(): Customer
    {
        $customer = Customer::query()->findOrFail($this->customerId);
        Gate::authorize('view', $customer);

        return $customer;
    }

    public function canRecord(): bool
    {
        $tenantId = $this->customer()->tenant_id;

        return Auth::user()->hasPermission(Permission::RecordContactAttempts, $tenantId) && Auth::user()->hasPermission(Permission::ViewPortfolio, $tenantId);
    }

    public function openRecord(): void
    {
        abort_unless($this->canRecord(), 403);
        $this->reset('channel', 'resultId', 'contractId', 'contactUsed', 'returnAt', 'text');
        $this->contactedAt = now()->format('Y-m-d\TH:i');
        $this->resetErrorBag();
        $this->showRecord = true;
    }

    /** O resultado escolhido define se o retorno aparece e se é obrigatório (R66, R73). */
    public function returnRule(): ?ReturnRule
    {
        return $this->resultId === '' ? null : ContactResult::query()->where('tenant_id', $this->customer()->tenant_id)->find((int) $this->resultId)?->return_rule;
    }

    /** R69c: o responsável financeiro é só uma sugestão de tela; nada é bloqueado. */
    public function responsibleHint(): ?string
    {
        $customer = $this->customer();
        $contract = $this->contractId === '' ? null : Contract::query()->with('customers')->find((int) $this->contractId);
        if ($contract === null) {
            return null;
        }
        $responsibles = $contract->financialResponsibles();

        return $responsibles->isEmpty() || $responsibles->contains('id', $customer->id) ? null : 'O responsável financeiro deste contrato é '.$responsibles->pluck('name')->implode(', ').'.';
    }

    public function record(): void
    {
        $customer = $this->customer();
        $this->validate(['channel' => ['required'], 'resultId' => ['required'], 'contactedAt' => ['required', 'date']], [], ['channel' => 'canal', 'resultId' => 'resultado', 'contactedAt' => 'data e hora do contato']);

        $text = $this->text;
        $contact = $this->contactUsed;
        if (DemoMode::enabled()) {
            // O que o visitante digita não fica gravado nem visível aos outros.
            $known = array_filter([$customer->phone, $customer->email]);
            $text = $text !== '' ? 'texto descartado na demonstração' : '';
            $contact = $contact !== '' && ! in_array($contact, $known, true) ? 'contato descartado na demonstração' : $contact;
        }

        try {
            app(ContactAttemptService::class)->record(Auth::user(), $customer, [
                'channel' => $this->channel, 'result_id' => $this->resultId, 'contract_id' => $this->contractId ?: null,
                'contact_used' => $contact, 'text' => $text, 'contacted_at' => $this->contactedAt, 'return_at' => $this->returnAt ?: null,
            ]);
        } catch (ContactRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->showRecord = false;
        $this->resetPage();
        $this->toast('Acionamento registrado');
    }

    public function askVoid(int $id): void
    {
        Gate::authorize('void', ContactAttempt::query()->where('customer_id', $this->customerId)->findOrFail($id));
        $this->voidingId = $id;
        $this->voidReason = '';
        $this->resetErrorBag();
    }

    public function void(): void
    {
        $attempt = ContactAttempt::query()->where('customer_id', $this->customerId)->findOrFail($this->voidingId);
        $this->validate(['voidReason' => ['required', 'max:300']], [], ['voidReason' => 'motivo da anulação']);
        $reason = DemoMode::enabled() ? 'motivo descartado na demonstração' : $this->voidReason;
        try {
            app(ContactAttemptService::class)->void(Auth::user(), $attempt, $reason);
        } catch (ContactRefused $e) {
            $this->toastError($e->getMessage());

            return;
        }
        $this->voidingId = null;
        $this->toast('Acionamento anulado');
    }

    public function render()
    {
        $customer = $this->customer();
        $tenantId = $customer->tenant_id;

        return view('livewire.customers.contact-attempts', [
            'customer' => $customer,
            'rows' => $this->paginateTable(ContactAttempt::query()->where('customer_id', $customer->id)->with(['result', 'user', 'contract', 'voidedBy'])
                ->orderByDesc('contacted_at')->orderByDesc('id')),
            'results' => ContactResult::query()->where('tenant_id', $tenantId)->where('active', true)->orderBy('position')->pluck('name', 'id'),
            'contracts' => Contract::query()->where('tenant_id', $tenantId)->whereHas('customers', fn ($q) => $q->whereKey($customer->id))->get(),
            'user' => Auth::user(),
        ]);
    }
}
