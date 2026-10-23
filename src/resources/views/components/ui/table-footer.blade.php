@props(['rows'])
{{-- Rodapé da tabela: quantos registros, seletor de registros por página (P22) e páginas. --}}
<div class="flex flex-wrap items-center justify-between gap-3 py-2 text-sm text-slate-500">
    <p>
        @if ($rows->total() === 0)
            Nenhum registro
        @else
            Exibindo {{ $rows->firstItem() }} a {{ $rows->lastItem() }} de {{ number_format($rows->total(), 0, ',', '.') }} {{ $rows->total() === 1 ? 'registro' : 'registros' }}
        @endif
    </p>
    <div class="flex items-center gap-4">
        <label class="flex items-center gap-2">
            Por página
            <x-ui.select wire:model.live="perPage" class="!w-auto !py-1">
                @foreach ([20, 50, 100] as $n)<option value="{{ $n }}">{{ $n }}</option>@endforeach
            </x-ui.select>
        </label>
        @if ($rows->hasPages())
            <div class="flex items-center gap-1">
                <x-ui.button size="sm" variant="secondary" wire:click="previousPage" :disabled="$rows->onFirstPage()">Anterior</x-ui.button>
                <span>Página {{ $rows->currentPage() }} de {{ $rows->lastPage() }}</span>
                <x-ui.button size="sm" variant="secondary" wire:click="nextPage" :disabled="! $rows->hasMorePages()">Próxima</x-ui.button>
            </div>
        @endif
    </div>
</div>
