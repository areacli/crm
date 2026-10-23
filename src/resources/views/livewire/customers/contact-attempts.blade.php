<x-ui.card title="Acionamentos">
    <x-slot:actions>
        @if ($this->canRecord())
            <x-ui.button wire:click="openRecord">Registrar acionamento</x-ui.button>
        @endif
    </x-slot:actions>

    @if ($rows->total() === 0)
        <x-ui.empty>Nenhum acionamento registrado.</x-ui.empty>
    @else
        <x-ui.table>
            <thead>
                <tr><x-ui.th>Contato</x-ui.th><x-ui.th>Resultado</x-ui.th><x-ui.th>Detalhes</x-ui.th><x-ui.th>Texto</x-ui.th><x-ui.th>Registrado por</x-ui.th></tr>
            </thead>
            <tbody class="divide-y divide-line">
                @foreach ($rows as $row)
                    <tr wire:key="a{{ $row->id }}" @class(['align-top', 'opacity-60' => $row->isVoided()])>
                        <td class="whitespace-nowrap px-2 py-1.5">{{ $row->contacted_at->format('d/m/Y H:i') }}<br><x-ui.badge>{{ $row->channel->getLabel() }}</x-ui.badge></td>
                        <td class="min-w-40 px-2 py-1.5"><span class="font-semibold">{{ $row->result->name }}</span><br><span class="text-xs text-ink-soft">{{ $row->result_type->getLabel() }}</span></td>
                        <td class="px-2 py-1.5 text-xs text-ink-soft">
                            @if ($row->contact_used)<span class="block">{{ $row->contact_used }}</span>@endif
                            @if ($row->contract)<span class="block">Contrato {{ $row->contract->code ?: '(sem código)' }}</span>@endif
                            @if ($row->return_at)<span class="block">Retorno {{ $row->return_at->format('d/m/Y H:i') }}</span>@endif
                            @if (! $row->contact_used && ! $row->contract && ! $row->return_at)—@endif
                        </td>
                        {{-- Texto puro (R72): escapado pelo Blade, com as quebras de linha preservadas por CSS. --}}
                        <td class="min-w-48 max-w-lg whitespace-pre-line px-2 py-1.5">{{ $row->text ?: '—' }}</td>
                        <td class="px-2 py-1.5 text-xs">{{ $row->user?->name ?: '—' }}<br><span class="text-ink-soft">{{ $row->created_at->format('d/m/Y H:i') }}</span>
                            @if ($row->isVoided())<br><span class="font-semibold text-red-700">Anulado: {{ $row->void_reason }} ({{ $row->voided_by ? $row->voidedBy?->name : '—' }}, {{ $row->voided_at->format('d/m/Y H:i') }})</span>@endif
                            @can('void', $row)<br><x-ui.button size="sm" variant="danger" class="mt-1" wire:click="askVoid({{ $row->id }})">Anular</x-ui.button>@endcan
                        </td>
                    </tr>
                @endforeach
            </tbody>
        </x-ui.table>
    @endif
    <x-ui.table-footer :rows="$rows" />

    <x-ui.modal wire:model="showRecord" size="xl" title="Registrar acionamento" description="Registre só o que for necessário para a cobrança.{{ \App\Demo\DemoMode::enabled() ? ' Na demonstração, o texto e o contato digitados são trocados por um texto fictício.' : '' }}">
        <div class="grid gap-3 sm:grid-cols-2">
        <x-ui.field label="Canal" name="channel" required>
            <x-ui.select wire:model="channel"><option value="">Escolha</option>@foreach (\App\Enums\ContactChannel::cases() as $c)<option value="{{ $c->value }}">{{ $c->getLabel() }}</option>@endforeach</x-ui.select>
        </x-ui.field>
        <x-ui.field label="Resultado" name="resultId" required>
            <x-ui.select wire:model.live="resultId"><option value="">Escolha</option>@foreach ($results as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select>
        </x-ui.field>
        <x-ui.field label="Contrato (opcional)" name="contractId" :help="$this->responsibleHint()">
            <x-ui.select wire:model.live="contractId"><option value="">Nenhum</option>@foreach ($contracts as $c)<option value="{{ $c->id }}">{{ $c->code ?? 'Sem código informado' }}</option>@endforeach</x-ui.select>
        </x-ui.field>
        </div>
        <div class="grid gap-3 sm:grid-cols-2">
        <x-ui.field label="Contato usado" name="contactUsed" help="Escolha o da ficha ou digite outro; o digitado fica só neste acionamento.">
            <x-ui.input wire:model="contactUsed" maxlength="300" list="contacts-{{ $customer->id }}" />
            <datalist id="contacts-{{ $customer->id }}">@foreach (array_filter([$customer->phone, $customer->email]) as $c)<option value="{{ $c }}">@endforeach</datalist>
        </x-ui.field>
        <x-ui.field label="Data e hora do contato" name="contactedAt" help="Padrão: agora. Até 7 dias atrás." required>
            <x-ui.input type="datetime-local" wire:model="contactedAt" />
        </x-ui.field>
        @if ($this->returnRule() !== \App\Enums\ReturnRule::NotAllowed && $resultId !== '')
            <x-ui.field label="Retorno combinado" name="returnAt" :required="$this->returnRule() === \App\Enums\ReturnRule::Required">
                <x-ui.input type="datetime-local" wire:model="returnAt" />
            </x-ui.field>
        @endif
        </div>
        <x-ui.field label="Texto" name="text" help="Texto puro, até 2000 caracteres.">
            <x-ui.textarea wire:model="text" rows="3" maxlength="2000" />
        </x-ui.field>
        <x-slot:footer>
            <x-ui.button variant="secondary" x-on:click="open = false">Cancelar</x-ui.button>
            <x-ui.button wire:click="record">Registrar</x-ui.button>
        </x-slot:footer>
    </x-ui.modal>

    @if ($voidingId)
        <div class="fixed inset-0 z-50 flex items-center justify-center p-4" role="dialog" aria-modal="true" aria-label="Anular acionamento">
            <div class="fixed inset-0 bg-brand-navy/50" wire:click="$set('voidingId', null)"></div>
            <div class="relative w-full max-w-md space-y-4 rounded-lg bg-white p-5 shadow-xl">
                <h2 class="text-lg font-bold text-ink">Anular acionamento</h2>
                <p class="text-sm text-ink-soft">O acionamento continua no histórico, marcado como anulado. A anulação não pode ser desfeita.</p>
                <x-ui.field label="Motivo da anulação" name="voidReason" required><x-ui.textarea wire:model="voidReason" rows="3" maxlength="300" /></x-ui.field>
                <div class="flex justify-end gap-2">
                    <x-ui.button variant="secondary" wire:click="$set('voidingId', null)">Cancelar</x-ui.button>
                    <x-ui.button variant="danger" wire:click="void">Anular</x-ui.button>
                </div>
            </div>
        </div>
    @endif
</x-ui.card>
