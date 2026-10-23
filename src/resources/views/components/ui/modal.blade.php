@props(['title', 'description' => null, 'size' => 'lg'])
{{-- Janela. Abre e fecha por uma propriedade booleana do componente: <x-ui.modal wire:model="showX" title="...">. --}}
<div x-data="{ open: $wire.$entangle('{{ $attributes->wire('model')->value() }}') }" x-show="open" x-cloak
     x-on:keydown.escape.window="open = false" class="fixed inset-0 z-50 flex items-center justify-center p-4"
     role="dialog" aria-modal="true" aria-label="{{ $title }}">
    <div class="fixed inset-0 bg-brand-navy/50" x-on:click="open = false"></div>
    <div x-show="open" x-trap.noscroll="open" @class(['relative flex max-h-[92vh] w-full flex-col rounded-lg bg-white shadow-xl', 'max-w-md' => $size === 'md', 'max-w-lg' => $size === 'lg', 'max-w-3xl' => $size === 'xl', 'max-w-2xl' => $size === 'lg2'])>
        <header class="flex shrink-0 items-start justify-between gap-4 border-b border-line px-4 py-3">
            <div>
                <h2 class="text-lg font-bold text-ink">{{ $title }}</h2>
                @if ($description)<p class="mt-1 text-sm text-ink-soft">{{ $description }}</p>@endif
            </div>
            <button type="button" class="text-ink-soft hover:text-ink" x-on:click="open = false" aria-label="Fechar">✕</button>
        </header>
        <div class="min-h-0 flex-1 space-y-3 overflow-y-auto px-4 py-3">{{ $slot }}</div>
        @isset($footer)
            <footer class="flex shrink-0 flex-wrap justify-end gap-2 border-t border-line px-4 py-2.5">{{ $footer }}</footer>
        @endisset
    </div>
</div>
