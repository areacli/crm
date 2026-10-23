<div class="space-y-4">
    <x-ui.page-header :title="($import->kind === 'reversals' ? 'Estornos' : ($import->kind === 'payments' ? 'Pagamentos — importação' : 'Importação')).' nº '.$import->id">
        <x-slot:actions>
            @can('confirm', $import)
                <x-ui.button wire:click="confirmImport" wire:confirm="{{ $import->kind === 'portfolio' ? 'Grava as linhas válidas na carteira, numa única operação. Confirmar?' : 'Aplica tudo numa única operação. Confirmar?' }}">Confirmar importação</x-ui.button>
                <x-ui.button variant="secondary" wire:click="discard" wire:confirm="Descartar esta importação?">Descartar</x-ui.button>
            @endcan
        </x-slot:actions>
    </x-ui.page-header>
    @include($resultView, ['import' => $import])
</div>
