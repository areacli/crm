@props(['title', 'description' => null])
<div class="flex flex-wrap items-start justify-between gap-3">
    <div>
        <h1 class="text-2xl font-bold text-slate-900">{{ $title }}</h1>
        @if ($description)<p class="mt-1 text-slate-500">{{ $description }}</p>@endif
    </div>
    @isset($actions)<div class="flex flex-wrap items-center gap-2">{{ $actions }}</div>@endisset
</div>
