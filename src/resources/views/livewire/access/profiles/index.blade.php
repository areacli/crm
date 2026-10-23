<div class="space-y-4">
    <x-ui.page-header title="Perfis">
        <x-slot:actions>@can('create', \App\Models\Profile::class)<x-ui.button :href="route('profiles.create')" wire:navigate>Novo perfil</x-ui.button>@endcan</x-slot:actions>
    </x-ui.page-header>

    @if ($several)
        <x-ui.field label="Credor" class="w-full sm:w-64"><x-ui.select wire:model.live="tenant"><option value="">Todos</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
    @endif

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhum perfil.</x-ui.empty>
    @else
        <x-ui.table>
            <thead><tr>@if ($several)<x-ui.th>Credor</x-ui.th>@endif<x-ui.th field="name" :sort="$sort" :dir="$dir">Perfil</x-ui.th><x-ui.th align="right">Permissões</x-ui.th><x-ui.th align="right">Usuários</x-ui.th><x-ui.th></x-ui.th></tr></thead>
            <tbody class="divide-y divide-line">
                @foreach ($rows as $p)
                    <tr wire:key="p{{ $p->id }}" class="hover:bg-surface">
                        @if ($several)<td class="px-2 py-1.5">{{ $p->tenant->name }}</td>@endif
                        <td class="px-2 py-1.5">{{ $p->name }}</td>
                        <td class="px-2 py-1.5 text-right">{{ count($p->permissions ?? []) }}</td>
                        <td class="px-2 py-1.5 text-right">{{ $p->memberships_count }}</td>
                        <td class="space-x-1 whitespace-nowrap px-2 py-1.5 text-right">
                            <x-ui.button size="sm" variant="secondary" :href="route('profiles.edit', $p->id)" wire:navigate>Editar</x-ui.button>
                            <x-ui.button size="sm" variant="danger" wire:click="delete({{ $p->id }})" wire:confirm="Apagar o perfil {{ $p->name }}?">Apagar</x-ui.button>
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />
</div>
