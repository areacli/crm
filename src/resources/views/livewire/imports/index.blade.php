@php use App\Support\Money; @endphp
<div class="space-y-4" wire:poll.5s>
    <x-ui.page-header :title="$heading">
        <x-slot:actions>
            @if ($canCreate)
                <x-ui.button :href="route($newRoute)" wire:navigate>{{ $newRoute === 'imports.create' ? 'Nova importação' : 'Importar pagamentos' }}</x-ui.button>
                @if ($newRoute === 'payments.create')<x-ui.button variant="secondary" :href="route('reversals.create')" wire:navigate>Importar estornos</x-ui.button>@endif
            @endif
        </x-slot:actions>
    </x-ui.page-header>

    @if ($several)
        <x-ui.field label="Credor" class="w-full sm:w-64"><x-ui.select wire:model.live="tenant"><option value="">Todos</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
    @endif

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhuma importação ainda.</x-ui.empty>
    @else
        <x-ui.table>
            <thead>
                <tr>
                    <x-ui.th field="id" :sort="$sort" :dir="$dir">Nº</x-ui.th>
                    @if ($several)<x-ui.th>Credor</x-ui.th>@endif
                    @if ($newRoute !== 'imports.create')<x-ui.th>Tipo</x-ui.th>@endif
                    <x-ui.th>Arquivo</x-ui.th>
                    @if ($newRoute === 'imports.create')<x-ui.th>Modo</x-ui.th>@endif
                    <x-ui.th>Situação</x-ui.th><x-ui.th align="right">Válidas</x-ui.th><x-ui.th align="right">Recusadas</x-ui.th>
                    @if ($newRoute === 'imports.create')<x-ui.th align="right">Valor</x-ui.th>@endif
                    <x-ui.th>Usuário</x-ui.th><x-ui.th field="created_at" :sort="$sort" :dir="$dir">Enviada em</x-ui.th>
                </tr>
            </thead>
            <tbody class="divide-y divide-slate-200">
                @foreach ($rows as $row)
                    <tr wire:key="i{{ $row->id }}" class="hover:bg-slate-50">
                        <td class="px-2 py-1.5"><a href="{{ route($showRoute, $row->id) }}" wire:navigate class="font-semibold text-blue-600 hover:underline">{{ $row->id }}</a></td>
                        @if ($several)<td class="px-2 py-1.5">{{ $row->tenant->name }}</td>@endif
                        @if ($newRoute !== 'imports.create')<td class="px-2 py-1.5">{{ $row->kind === 'reversals' ? 'Estornos' : 'Pagamentos' }}</td>@endif
                        <td class="max-w-xs truncate px-2 py-1.5">{{ $row->original_name }}</td>
                        @if ($newRoute === 'imports.create')<td class="px-2 py-1.5"><x-ui.badge>{{ $row->mode->getLabel() }}</x-ui.badge></td>@endif
                        <td class="px-2 py-1.5"><x-ui.badge :color="$row->status->getColor()">{{ $row->status->getLabel() }}</x-ui.badge></td>
                        <td class="px-2 py-1.5 text-right">{{ isset($row->summary['valid']) ? number_format($row->summary['valid'], 0, ',', '.') : '—' }}</td>
                        <td class="px-2 py-1.5 text-right">{{ isset($row->summary['rejected']) ? number_format($row->summary['rejected'], 0, ',', '.') : '—' }}</td>
                        @if ($newRoute === 'imports.create')<td class="px-2 py-1.5 text-right">{{ isset($row->summary['amount_cents']) ? 'R$ '.Money::format((int) $row->summary['amount_cents']) : '—' }}</td>@endif
                        <td class="px-2 py-1.5">{{ $row->user?->name ?: '—' }}</td>
                        <td class="whitespace-nowrap px-2 py-1.5">{{ $row->created_at->format('d/m/Y H:i') }}</td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />
</div>
