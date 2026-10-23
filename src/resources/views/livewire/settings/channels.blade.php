<div class="space-y-4">
    <x-ui.page-header title="Configuração" />
    <x-ui.tabs :tabs="\App\Support\Navigation::settingsTabs(auth()->user())" />

    <div class="flex flex-wrap items-end justify-between gap-3">
        <x-ui.field label="Buscar" class="w-full sm:w-72"><x-ui.input type="search" wire:model.live.debounce.400ms="search" placeholder="Código ou descrição" /></x-ui.field>
        <x-ui.button wire:click="openCreate">Novo canal</x-ui.button>
    </div>

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhum canal cadastrado.</x-ui.empty>
    @else
        <x-ui.table>
            <thead>
                <tr>
                    @if ($several)<x-ui.th>Credor</x-ui.th>@endif
                    <x-ui.th field="code" :sort="$sort" :dir="$dir">Código</x-ui.th><x-ui.th>Tipo</x-ui.th>
                    <x-ui.th field="description" :sort="$sort" :dir="$dir">Descrição</x-ui.th><x-ui.th>Ativo</x-ui.th><x-ui.th></x-ui.th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-200">
                @foreach ($rows as $row)
                    <tr wire:key="ch{{ $row->id }}" class="hover:bg-slate-50">
                        @if ($several)<td class="px-2 py-1.5">{{ $row->tenant->name }}</td>@endif
                        <td class="px-2 py-1.5 font-mono">{{ $row->code }}</td>
                        <td class="px-2 py-1.5"><x-ui.badge>{{ $row->type->getLabel() }}</x-ui.badge></td>
                        <td class="px-2 py-1.5">{{ $row->description }}</td>
                        <td class="px-2 py-1.5">{{ $row->active ? 'Sim' : 'Não' }}</td>
                        <td class="space-x-2 whitespace-nowrap px-2 py-1.5 text-right">
                            <x-ui.button size="sm" variant="secondary" wire:click="openEdit({{ $row->id }})">Editar</x-ui.button>
                            @if ($row->payments_count === 0)
                                <x-ui.button size="sm" variant="danger" wire:click="delete({{ $row->id }})" wire:confirm="Apagar o canal {{ $row->code }}?">Apagar</x-ui.button>
                            @endif
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />

    <x-ui.modal wire:model="showForm" :title="$editingId ? 'Editar canal' : 'Novo canal'">
        @if (! $editingId && $several)
            <x-ui.field label="Credor" name="tenantId" required><x-ui.select wire:model="tenantId"><option value="">Escolha</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        @endif
        <x-ui.field label="Tipo" name="type" required><x-ui.select wire:model="type">@foreach ($types as $t)<option value="{{ $t->value }}">{{ $t->getLabel() }}</option>@endforeach</x-ui.select></x-ui.field>
        <x-ui.field label="Código" name="code" required :help="$this->hasPayments() ? 'O canal tem pagamentos: o código não muda.' : null"><x-ui.input wire:model="code" maxlength="100" :disabled="$this->hasPayments()" /></x-ui.field>
        <x-ui.field label="Descrição" name="description" required><x-ui.input wire:model="description" maxlength="200" /></x-ui.field>
        <x-ui.checkbox wire:model="active" label="Ativo" />
        <x-slot:footer>
            <x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button>
            <x-ui.button wire:click="save">Salvar</x-ui.button>
        </x-slot:footer>
    </x-ui.modal>
</div>
