<div class="space-y-4">
    <x-ui.page-header title="Configuração" />
    <x-ui.tabs :tabs="\App\Support\Navigation::settingsTabs(auth()->user())" />

    <form wire:submit="save" class="space-y-4">
        @if ($tenants->count() > 1)
            <x-ui.field label="Credor" class="max-w-sm"><x-ui.select wire:model.live="tenantId">@foreach ($tenants as $t)<option value="{{ $t->id }}">{{ $t->name }}</option>@endforeach</x-ui.select></x-ui.field>
        @endif

        <x-ui.card title="Faixas de atraso (dias)" description="Começam em 1 dia, sem buraco nem sobreposição; a última é aberta (deixe o fim vazio).">
            <div class="space-y-3">
                @foreach ($brackets as $i => $b)
                    <div class="flex items-end gap-3" wire:key="b{{ $i }}">
                        <x-ui.field label="De" class="w-32"><x-ui.input type="number" wire:model="brackets.{{ $i }}.from" /></x-ui.field>
                        <x-ui.field label="Até" class="w-32"><x-ui.input type="number" wire:model="brackets.{{ $i }}.to" /></x-ui.field>
                        <x-ui.button variant="danger" size="sm" wire:click="removeBracket({{ $i }})">Remover</x-ui.button>
                    </div>
                @endforeach
                <x-ui.button variant="secondary" size="sm" wire:click="addBracket">Adicionar faixa</x-ui.button>
            </div>
        </x-ui.card>

        <x-ui.card title="Títulos a vencer">
            <x-ui.radio-group wire:model="upcoming" :options="[
                'separate' => 'Separado: coluna própria nos totais e na ficha, fora das faixas',
                'summed' => 'Somado: entra no total em cobrança; o vencido continua visível à parte',
                'detail_only' => 'Só na ficha: fora dos totais',
            ]" />
        </x-ui.card>

        <x-ui.button type="submit">Salvar</x-ui.button>
    </form>
</div>
