@props(['title', 'description' => null, 'size' => 'lg'])
{{-- Janela. Abre e fecha por uma propriedade booleana do componente: <x-ui.modal wire:model="showX" title="...">. --}}
<div x-data="{ open: $wire.$entangle('{{ $attributes->wire('model')->value() }}') }" x-show="open" x-cloak
     x-on:keydown.escape.window="open = false" class="fixed inset-0 z-50 flex items-start justify-center overflow-y-auto p-4 sm:items-center"
     role="dialog" aria-modal="true" aria-label="{{ $title }}">
    <div class="fixed inset-0 bg-slate-900/50" x-on:click="open = false"></div>
    <div x-show="open" x-trap.noscroll="open" @class(['relative w-full rounded-lg bg-white shadow-xl', 'max-w-md' => $size === 'md', 'max-w-lg' => $size === 'lg', 'max-w-3xl' => $size === 'xl'])>
        <header class="flex items-start justify-between gap-4 border-b border-slate-200 px-5 py-4">
            <div>
                <h2 class="text-lg font-bold text-slate-900">{{ $title }}</h2>
                @if ($description)<p class="mt-1 text-sm text-slate-500">{{ $description }}</p>@endif
            </div>
            <button type="button" class="text-slate-500 hover:text-slate-900" x-on:click="open = false" aria-label="Fechar">✕</button>
        </header>
        <div class="space-y-4 px-5 py-4">{{ $slot }}</div>
        @isset($footer)
            <footer class="flex flex-wrap justify-end gap-2 border-t border-slate-200 px-5 py-3">{{ $footer }}</footer>
        @endisset
    </div>
</div>
