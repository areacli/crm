@props(['variant' => 'primary', 'type' => 'button', 'href' => null, 'size' => 'md'])
@php
    $classes = [
        'inline-flex items-center justify-center gap-2 rounded-md font-semibold transition disabled:cursor-not-allowed disabled:opacity-50 data-loading:opacity-60',
        match ($size) { 'sm' => 'px-3 py-1.5 text-sm', default => 'px-4 py-2 text-base' },
        match ($variant) {
            'secondary' => 'border border-slate-300 bg-white text-slate-900 hover:bg-slate-50',
            'danger' => 'border border-red-600 bg-white text-red-600 hover:bg-red-50',
            'ghost' => 'text-blue-600 hover:underline',
            default => 'bg-blue-600 text-white hover:bg-blue-700',
        },
    ];
@endphp
@if ($href)
    <a href="{{ $href }}" {{ $attributes->class($classes) }}>{{ $slot }}</a>
@else
    <button type="{{ $type }}" {{ $attributes->class($classes) }}>{{ $slot }}</button>
@endif
