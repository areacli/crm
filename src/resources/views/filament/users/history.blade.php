@php
    $labels = [
        'login' => 'Entrou', 'logout' => 'Saiu', 'login_refused' => 'Entrada recusada', 'locked' => 'Bloqueado por tentativas',
        'permission_denied' => 'Acesso recusado por falta de permissão', 'user_created' => 'Usuário criado',
        'membership_linked' => 'Ligado ao credor', 'profile_changed' => 'Perfil alterado', 'membership_deactivated' => 'Acesso desativado',
        'membership_reactivated' => 'Acesso reativado', 'user_renamed' => 'Nome alterado', 'password_reset' => 'Senha redefinida',
        'password_changed' => 'Trocou a senha',
    ];
@endphp
<div class="space-y-2 text-sm">
    @forelse ($events as $event)
        @php($details = $event->details ? json_decode($event->details, true) : [])
        <div class="rounded-lg border border-gray-200 p-2 dark:border-white/10">
            <div class="font-medium">{{ $labels[$event->event] ?? $event->event }}</div>
            <div class="text-gray-500">{{ \Illuminate\Support\Carbon::parse($event->occurred_at)->format('d/m/Y H:i') }}
                @if (isset($details['before'], $details['after'])) — de {{ is_array($details['before']) ? ($details['before']['name'] ?? '') : $details['before'] }} para {{ is_array($details['after']) ? ($details['after']['name'] ?? '') : $details['after'] }} @endif
                @if (isset($details['profile']) && ! isset($details['before'])) — perfil {{ $details['profile'] }} @endif
            </div>
        </div>
    @empty
        <p>Nenhum registro.</p>
    @endforelse
</div>
