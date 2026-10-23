<div class="space-y-4">
    <x-ui.page-header title="Usuários">
        <x-slot:actions>@can('create', \App\Models\Membership::class)<x-ui.button wire:click="open('new')">Novo usuário</x-ui.button>@endcan</x-slot:actions>
    </x-ui.page-header>

    <div class="flex flex-wrap items-end gap-3">
        <x-ui.field label="Buscar" class="w-full sm:w-72"><x-ui.input type="search" wire:model.live.debounce.400ms="search" placeholder="Nome ou e-mail" /></x-ui.field>
        @if ($several)
            <x-ui.field label="Credor" class="w-full sm:w-52"><x-ui.select wire:model.live="tenant"><option value="">Todos</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
        @endif
    </div>

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhum usuário.</x-ui.empty>
    @else
        <x-ui.table>
            <thead><tr><x-ui.th>Nome</x-ui.th><x-ui.th>E-mail</x-ui.th>@if ($several)<x-ui.th>Credor</x-ui.th>@endif<x-ui.th>Perfil</x-ui.th><x-ui.th>Ativo</x-ui.th><x-ui.th>Último acesso</x-ui.th><x-ui.th></x-ui.th></tr></thead>
            <tbody class="divide-y divide-slate-200">
                @foreach ($rows as $m)
                    <tr wire:key="m{{ $m->id }}" class="hover:bg-slate-50">
                        <td class="px-2 py-1.5">{{ $m->user->name }}</td>
                        <td class="px-2 py-1.5">{{ $m->user->email }}</td>
                        @if ($several)<td class="px-2 py-1.5">{{ $m->tenant->name }}</td>@endif
                        <td class="px-2 py-1.5">{{ $m->profile->name }}</td>
                        <td class="px-2 py-1.5">{{ $m->active ? 'Sim' : 'Não' }}</td>
                        <td class="whitespace-nowrap px-2 py-1.5">{{ $m->user->last_login_at?->format('d/m/Y H:i') ?: '—' }}</td>
                        <td class="space-x-1 whitespace-nowrap px-2 py-1.5 text-right">
                            @can('changeProfile', $m)<x-ui.button size="sm" variant="secondary" wire:click="open('profile', {{ $m->id }})">Mudar o perfil</x-ui.button>@endcan
                            @if ($personal($m))
                                <x-ui.button size="sm" variant="secondary" wire:click="open('rename', {{ $m->id }})">Alterar o nome</x-ui.button>
                                <x-ui.button size="sm" variant="secondary" wire:click="resetPassword({{ $m->id }})" wire:confirm="Gera uma senha temporária, válida por 72 horas, mostrada uma única vez. A senha anterior deixa de valer. Redefinir?">Redefinir a senha</x-ui.button>
                            @endif
                            @can('deactivate', $m)<x-ui.button size="sm" variant="danger" wire:click="setActive({{ $m->id }}, false)" wire:confirm="Desativa o acesso da pessoa a este credor. Ela segue nos outros credores, se houver. Desativar?">Desativar</x-ui.button>@endcan
                            @can('reactivate', $m)<x-ui.button size="sm" variant="secondary" wire:click="setActive({{ $m->id }}, true)">Reativar</x-ui.button>@endcan
                            <x-ui.button size="sm" variant="ghost" wire:click="open('history', {{ $m->id }})">Histórico</x-ui.button>
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />

    <x-ui.modal wire:model="showModal" size="lg" :title="match ($modal) { 'new' => 'Novo usuário', 'profile' => 'Mudar o perfil', 'rename' => 'Alterar o nome', 'history' => 'Histórico de '.($target?->user->email ?? ''), default => '' }">
        @if ($modal === 'new')
            <x-ui.alert>Se o e-mail já pertence a alguém que atua em outro credor, essa pessoa é ligada a este credor na hora e recebe um aviso. Se não, o usuário é criado com uma senha temporária, mostrada uma única vez.</x-ui.alert>
            @if ($several)<x-ui.field label="Credor" name="tenantId" required><x-ui.select wire:model.live="tenantId"><option value="">Escolha</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>@endif
            <x-ui.field label="E-mail" name="email" required><x-ui.input type="email" wire:model="email" maxlength="254" /></x-ui.field>
            <x-ui.field label="Nome (para quem ainda não existe)" name="name"><x-ui.input wire:model="name" maxlength="150" /></x-ui.field>
            <x-ui.field label="Perfil" name="profileId" required><x-ui.select wire:model="profileId"><option value="">Escolha</option>@foreach ($profiles as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
            <x-slot:footer><x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button><x-ui.button wire:click="addUser">Salvar</x-ui.button></x-slot:footer>
        @elseif ($modal === 'profile')
            <x-ui.field label="Perfil" name="profileId" required><x-ui.select wire:model="profileId">@foreach ($profiles as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
            <x-slot:footer><x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button><x-ui.button wire:click="changeProfile">Salvar</x-ui.button></x-slot:footer>
        @elseif ($modal === 'rename')
            <x-ui.field label="Nome" name="name" required><x-ui.input wire:model="name" maxlength="150" /></x-ui.field>
            <x-slot:footer><x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button><x-ui.button wire:click="rename">Salvar</x-ui.button></x-slot:footer>
        @elseif ($modal === 'history')
            @php
                $labels = ['login' => 'Entrou', 'logout' => 'Saiu', 'login_refused' => 'Entrada recusada', 'locked' => 'Bloqueado por tentativas', 'permission_denied' => 'Acesso recusado por falta de permissão', 'user_created' => 'Usuário criado', 'membership_linked' => 'Ligado ao credor', 'profile_changed' => 'Perfil alterado', 'membership_deactivated' => 'Acesso desativado', 'membership_reactivated' => 'Acesso reativado', 'user_renamed' => 'Nome alterado', 'password_reset' => 'Senha redefinida', 'password_changed' => 'Trocou a senha'];
            @endphp
            <div class="max-h-96 space-y-2 overflow-y-auto text-sm">
                @forelse ($events as $event)
                    @php($details = $event->details ? json_decode($event->details, true) : [])
                    <div class="rounded border border-slate-200 p-2">
                        <p class="font-semibold">{{ $labels[$event->event] ?? $event->event }}</p>
                        <p class="text-slate-500">{{ \Illuminate\Support\Carbon::parse($event->occurred_at)->format('d/m/Y H:i') }}
                            @if (isset($details['before'], $details['after'])) — de {{ is_array($details['before']) ? ($details['before']['name'] ?? '') : $details['before'] }} para {{ is_array($details['after']) ? ($details['after']['name'] ?? '') : $details['after'] }} @endif
                            @if (isset($details['profile']) && ! isset($details['before'])) — perfil {{ $details['profile'] }} @endif</p>
                    </div>
                @empty
                    <p class="text-slate-500">Nenhum registro.</p>
                @endforelse
            </div>
        @endif
    </x-ui.modal>
</div>
