<div class="space-y-4">
    <x-ui.page-header title="Acionamentos" />

    <div class="grid gap-3 sm:grid-cols-2 lg:grid-cols-4">
        <x-ui.field label="De"><x-ui.input type="date" wire:model.live="from" /></x-ui.field>
        <x-ui.field label="Até"><x-ui.input type="date" wire:model.live="until" /></x-ui.field>
        <x-ui.field label="Operador"><x-ui.select wire:model.live="operator"><option value="">Todos</option>@foreach ($operators as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        <x-ui.field label="Canal"><x-ui.select wire:model.live="channel"><option value="">Todos</option>@foreach ($channels as $c)<option value="{{ $c->value }}">{{ $c->getLabel() }}</option>@endforeach</x-ui.select></x-ui.field>
        <x-ui.field label="Resultado"><x-ui.select wire:model.live="result"><option value="">Todos</option>@foreach ($results as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        <x-ui.field label="Tipo"><x-ui.select wire:model.live="type"><option value="">Todos</option>@foreach ($types as $t)<option value="{{ $t->value }}">{{ $t->getLabel() }}</option>@endforeach</x-ui.select></x-ui.field>
        @if ($several)
            <x-ui.field label="Credor"><x-ui.select wire:model.live="tenant"><option value="">Todos</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        @endif
        <div class="flex items-end"><x-ui.checkbox wire:model.live="includeVoided" label="Incluir anulados" /></div>
    </div>

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhum acionamento no período.</x-ui.empty>
    @else
        <x-ui.table>
            <thead>
                <tr>
                    <x-ui.th>Contato</x-ui.th>
                    @if ($several)<x-ui.th>Credor</x-ui.th>@endif
                    <x-ui.th>Cliente</x-ui.th><x-ui.th>Contrato</x-ui.th><x-ui.th>Canal</x-ui.th><x-ui.th>Resultado</x-ui.th><x-ui.th>Tipo</x-ui.th><x-ui.th>Operador</x-ui.th><x-ui.th>Retorno</x-ui.th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-200">
                @foreach ($rows as $row)
                    <tr wire:key="r{{ $row->id }}" @class(['hover:bg-slate-50', 'opacity-60' => $row->isVoided()])>
                        <td class="whitespace-nowrap px-2 py-1.5">{{ $row->contacted_at->format('d/m/Y H:i') }}</td>
                        @if ($several)<td class="px-2 py-1.5">{{ $row->tenant->name }}</td>@endif
                        <td class="px-2 py-1.5"><a href="{{ route('customers.show', $row->customer_id) }}" wire:navigate class="font-semibold text-blue-600 hover:underline">{{ $row->customer->name }}</a></td>
                        <td class="px-2 py-1.5">{{ $row->contract?->code ?: '—' }}</td>
                        <td class="px-2 py-1.5"><x-ui.badge>{{ $row->channel->getLabel() }}</x-ui.badge></td>
                        <td class="px-2 py-1.5">{{ $row->result->name }}@if ($row->isVoided())<br><span class="text-xs text-red-700">Anulado</span>@endif</td>
                        <td class="px-2 py-1.5"><x-ui.badge :color="$row->result_type->getColor()">{{ $row->result_type->getLabel() }}</x-ui.badge></td>
                        <td class="px-2 py-1.5">{{ $row->user?->name ?: '—' }}</td>
                        <td class="whitespace-nowrap px-2 py-1.5">{{ $row->return_at?->format('d/m/Y H:i') ?: '—' }}</td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />
</div>
