<div class="space-y-4">
    <x-ui.page-header title="Configuração" />
    <x-ui.tabs :tabs="\App\Support\Navigation::settingsTabs(auth()->user())" />

    <div class="flex flex-wrap items-end justify-between gap-3">
        @if ($several)
            <x-ui.field label="Credor" class="w-full sm:w-64"><x-ui.select wire:model.live="tenant">@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        @else
            <span></span>
        @endif
        <x-ui.button wire:click="openCreate">Novo resultado</x-ui.button>
    </div>

    @if ($rows->isEmpty())
        <x-ui.empty>Nenhum resultado.</x-ui.empty>
    @else
        <x-ui.table>
            <thead><tr><x-ui.th>Nome</x-ui.th><x-ui.th>Tipo</x-ui.th><x-ui.th>Retorno</x-ui.th><x-ui.th align="right">Acionamentos</x-ui.th><x-ui.th>Ativo</x-ui.th><x-ui.th></x-ui.th></tr></thead>
            <tbody class="divide-y divide-line">
                @foreach ($rows as $row)
                    <tr wire:key="cr{{ $row->id }}" class="hover:bg-surface">
                        <td class="px-2 py-1.5">{{ $row->name }}</td>
                        <td class="px-2 py-1.5"><x-ui.badge :color="$row->type->getColor()">{{ $row->type->getLabel() }}</x-ui.badge></td>
                        <td class="px-2 py-1.5">{{ $row->return_rule->getLabel() }}</td>
                        <td class="px-2 py-1.5 text-right">{{ $row->attempts_count }}</td>
                        <td class="px-2 py-1.5">{{ $row->active ? 'Sim' : 'Não' }}</td>
                        <td class="space-x-1 whitespace-nowrap px-2 py-1.5 text-right">
                            <x-ui.button size="sm" variant="secondary" wire:click="move({{ $row->id }}, -1)" aria-label="Subir">↑</x-ui.button>
                            <x-ui.button size="sm" variant="secondary" wire:click="move({{ $row->id }}, 1)" aria-label="Descer">↓</x-ui.button>
                            <x-ui.button size="sm" variant="secondary" wire:click="openEdit({{ $row->id }})">Editar</x-ui.button>
                            @if ($row->active)
                                <x-ui.button size="sm" variant="danger" wire:click="setActive({{ $row->id }}, false)" wire:confirm="Desativar? O resultado some da lista de escolha e continua nos acionamentos antigos.">Desativar</x-ui.button>
                            @else
                                <x-ui.button size="sm" variant="secondary" wire:click="setActive({{ $row->id }}, true)">Reativar</x-ui.button>
                            @endif
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif

    <x-ui.modal wire:model="showForm" :title="$editingId ? 'Editar resultado' : 'Novo resultado'">
        <x-ui.field label="Nome" name="name" required><x-ui.input wire:model="name" maxlength="100" /></x-ui.field>
        <x-ui.field label="Tipo" name="type" required help="Não muda depois de criado.">
            <x-ui.select wire:model="type" :disabled="(bool) $editingId">@foreach ($types as $t)<option value="{{ $t->value }}">{{ $t->getLabel() }}</option>@endforeach</x-ui.select>
        </x-ui.field>
        <x-ui.field label="Data de retorno" name="returnRule" required><x-ui.select wire:model="returnRule">@foreach ($rules as $r)<option value="{{ $r->value }}">{{ $r->getLabel() }}</option>@endforeach</x-ui.select></x-ui.field>
        <x-slot:footer>
            <x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button>
            <x-ui.button wire:click="save">Salvar</x-ui.button>
        </x-slot:footer>
    </x-ui.modal>
</div>
