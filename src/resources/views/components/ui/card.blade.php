@props(['title' => null, 'description' => null])
<section {{ $attributes->class('rounded-lg border border-slate-200 bg-white') }}>
    @if ($title || isset($actions))
        <header class="flex flex-wrap items-center justify-between gap-3 border-b border-slate-200 px-3 py-2">
            <div>
                @if ($title)<h2 class="text-lg font-bold text-blue-600">{{ $title }}</h2>@endif
                @if ($description)<p class="text-sm text-slate-500">{{ $description }}</p>@endif
            </div>
            @isset($actions)<div class="flex items-center gap-2">{{ $actions }}</div>@endisset
        </header>
    @endif
    <div class="p-3">{{ $slot }}</div>
</section>
