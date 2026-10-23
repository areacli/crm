<div x-data="{ open: false }" class="relative" x-on:keydown.escape.window="open = false">
    <button type="button" class="relative rounded p-2 hover:bg-blue-700" x-on:click="open = !open" aria-label="Avisos" x-bind:aria-expanded="open">
        <svg class="h-5 w-5" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" stroke-linejoin="round" d="M15 17h5l-1.4-1.4A2 2 0 0 1 18 14.2V11a6 6 0 1 0-12 0v3.2a2 2 0 0 1-.6 1.4L4 17h5m6 0a3 3 0 1 1-6 0"/></svg>
        @if ($count > 0)<span class="absolute right-0 top-0 flex h-4 min-w-4 items-center justify-center rounded-full bg-blue-600 px-1 text-xs font-bold text-slate-900">{{ $count }}</span>@endif
    </button>
    <div x-show="open" x-cloak x-on:click.outside="open = false" class="absolute right-0 mt-2 w-80 rounded-md border border-slate-200 bg-white text-slate-900 shadow-lg">
        <div class="flex items-center justify-between border-b border-slate-200 px-4 py-2">
            <span class="text-sm font-semibold">Avisos</span>
            @if ($count > 0)<button type="button" wire:click="markAllRead" class="text-sm text-blue-600 hover:underline">Marcar como lidos</button>@endif
        </div>
        @forelse ($unread as $n)
            <div class="border-b border-slate-200 px-4 py-2 text-sm last:border-b-0">
                <p class="font-semibold">{{ $n->data['title'] ?? '' }}</p>
                <p class="text-slate-500">{{ $n->data['body'] ?? '' }}</p>
                <p class="text-xs text-slate-500">{{ $n->created_at->format('d/m/Y H:i') }}</p>
            </div>
        @empty
            <p class="px-4 py-3 text-sm text-slate-500">Nenhum aviso novo.</p>
        @endforelse
    </div>
</div>
