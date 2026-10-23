@props(['title', 'description' => null])
<div class="flex flex-wrap items-start justify-between gap-3">
    <div>
        <h1 class="text-2xl font-bold text-ink">{{ $title }}</h1>
        @if ($description)<p class="mt-1 text-ink-soft">{{ $description }}</p>@endif
    </div>
    @isset($actions)<div class="flex flex-wrap items-center gap-2">{{ $actions }}</div>@endisset
</div>
