<div class="space-y-6">
    <x-ui.page-header :title="$heading">
        <x-slot:actions><x-ui.button variant="secondary" wire:click="template">Baixar a planilha-modelo</x-ui.button></x-slot:actions>
    </x-ui.page-header>

    @include('livewire.imports._columns', ['columns' => $columns])

    <x-ui.card title="Enviar arquivo">
        <form wire:submit="send" class="space-y-4">
            @if ($tenants->count() > 1)
                <x-ui.field label="Credor" name="tenantId" required class="max-w-sm">
                    <x-ui.select wire:model="tenantId"><option value="">Escolha</option>@foreach ($tenants as $t)<option value="{{ $t->id }}">{{ $t->name }}</option>@endforeach</x-ui.select>
                </x-ui.field>
            @endif
            <x-ui.field label="Arquivo CSV" name="file" required
                :help="'Separador ponto e vírgula, UTF-8 ou Windows-1252, até 50 MB e 200.000 linhas.'.($demo ? ' Na demonstração, seu arquivo é descartado sem ser lido e trocado por um arquivo fictício.' : '')">
                <input type="file" wire:model="file" accept=".csv,text/csv,text/plain" class="block w-full text-sm file:mr-3 file:rounded-md file:border-0 file:bg-slate-100 file:px-3 file:py-2 file:font-semibold hover:file:bg-slate-200">
                <p wire:loading wire:target="file" class="text-sm text-slate-500">Enviando o arquivo…</p>
            </x-ui.field>
            <x-ui.button type="submit" wire:loading.attr="disabled" wire:target="file,send">Enviar e conferir</x-ui.button>
        </form>
    </x-ui.card>
</div>
