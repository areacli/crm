@php use App\Support\Document; use App\Support\Money; @endphp
<div class="space-y-4">
    <x-ui.page-header title="Clientes" />

    <div class="flex flex-wrap items-end gap-3">
        <x-ui.field label="Buscar" class="w-full sm:w-80">
            <x-ui.input type="search" wire:model.live.debounce.400ms="search" placeholder="Nome ou documento" />
        </x-ui.field>
        <x-ui.field label="Faixa de atraso" class="w-full sm:w-52">
            <x-ui.select wire:model.live="bracket">
                <option value="">Todas</option>
                @foreach ($brackets as $value => $label)<option value="{{ $value }}">{{ $label }}</option>@endforeach
            </x-ui.select>
        </x-ui.field>
        @if ($several)
            <x-ui.field label="Credor" class="w-full sm:w-52">
                <x-ui.select wire:model.live="tenant">
                    <option value="">Todos</option>
                    @foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach
                </x-ui.select>
            </x-ui.field>
        @endif
    </div>

    @if ($rows->total() === 0)
        <x-ui.empty>
            <p class="font-semibold text-ink">Nenhum cliente em cobrança</p>
            <p>Importe a carteira para ver os clientes aqui.</p>
        </x-ui.empty>
    @else
        <x-ui.table>
            <thead>
                <tr>
                    @if ($several)<x-ui.th>Credor</x-ui.th>@endif
                    <x-ui.th field="name" :sort="$sort" :dir="$dir">Nome</x-ui.th>
                    <x-ui.th>Documento</x-ui.th>
                    <x-ui.th field="bills_count" :sort="$sort" :dir="$dir" align="right">Títulos</x-ui.th>
                    <x-ui.th field="overdue_cents" :sort="$sort" :dir="$dir" align="right">Vencido</x-ui.th>
                    <x-ui.th field="upcoming_cents" :sort="$sort" :dir="$dir" align="right">A vencer</x-ui.th>
                    <x-ui.th field="max_days_overdue" :sort="$sort" :dir="$dir" align="right">Maior atraso</x-ui.th>
                    <x-ui.th>Faixa</x-ui.th>
                </tr>
            </thead>
            <tbody class="divide-y divide-line">
                @foreach ($rows as $row)
                    <tr wire:key="c{{ $row->id }}" class="hover:bg-surface">
                        @if ($several)<td class="px-2 py-1.5">{{ $row->tenant->name }}</td>@endif
                        <td class="px-2 py-1.5"><a href="{{ route('customers.show', $row->id) }}" wire:navigate class="font-semibold text-brand-blue hover:underline">{{ $row->name }}</a></td>
                        <td class="px-2 py-1.5 font-mono">{{ Document::mask($row->document) }}</td>
                        <td class="px-2 py-1.5 text-right">{{ number_format($row->bills_count, 0, ',', '.') }}</td>
                        <td class="px-2 py-1.5 text-right">R$ {{ Money::format((int) $row->overdue_cents) }}</td>
                        <td class="px-2 py-1.5 text-right">{{ $this->upcomingText($row, $settings) }}</td>
                        <td class="px-2 py-1.5 text-right">{{ $row->max_days_overdue === null ? '—' : $row->max_days_overdue.' dias' }}</td>
                        <td class="px-2 py-1.5"><x-ui.badge>{{ $portfolio->bracketLabel($row->tenant_id, $row->max_days_overdue === null ? null : (int) $row->max_days_overdue) }}</x-ui.badge></td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />
</div>
