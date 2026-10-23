@php use App\Support\Document; @endphp
<div class="space-y-6">
    <x-ui.page-header :title="$customer->name">
        <x-slot:actions>
            @if ($this->canTransfer())
                <x-ui.button variant="secondary" wire:click="openTransfer">Transferir crédito</x-ui.button>
            @endif
        </x-slot:actions>
    </x-ui.page-header>

    <x-ui.card title="Dados">
        <dl class="grid grid-cols-2 gap-4 md:grid-cols-5">
            <x-ui.stat label="Nome" :value="$customer->name" small />
            <x-ui.stat label="Documento" :value="Document::format($customer->document)" small />
            <x-ui.stat label="Telefone" :value="$customer->phone ?: '—'" small />
            <x-ui.stat label="E-mail" :value="$customer->email ?: '—'" small />
            <x-ui.stat label="Credor" :value="$customer->tenant->name" small />
        </dl>
    </x-ui.card>

    @include('livewire.customers._bills', ['customer' => $customer])

    <livewire:customers.contact-attempts :customer-id="$customer->id" :key="'attempts'.$customer->id" />

    <x-ui.modal wire:model="showTransfer" title="Transferir crédito" description="O crédito é do contrato. A transferência move crédito disponível para outro contrato do mesmo credor, com motivo, e fica registrada nos dois contratos.">
        <x-ui.field label="Contrato de origem" name="fromContract" required>
            <x-ui.select wire:model="fromContract">
                @foreach ($this->creditContracts() as $c)
                    <option value="{{ $c->id }}">{{ $c->code ? 'Contrato '.$c->code : 'Sem contrato informado' }} — crédito R$ {{ App\Support\Money::format($c->creditCents()) }}</option>
                @endforeach
            </x-ui.select>
        </x-ui.field>
        <x-ui.field label="Código do contrato de destino" name="toCode" required><x-ui.input wire:model="toCode" maxlength="100" /></x-ui.field>
        <x-ui.field label="Valor (R$)" name="amount" required><x-ui.input wire:model="amount" placeholder="250,00" /></x-ui.field>
        <x-ui.field label="Motivo" name="reason" required><x-ui.textarea wire:model="reason" rows="3" maxlength="300" /></x-ui.field>
        <x-slot:footer>
            <x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button>
            <x-ui.button wire:click="transfer">Transferir</x-ui.button>
        </x-slot:footer>
    </x-ui.modal>
</div>
