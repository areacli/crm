@props(['color' => 'gray'])
<span {{ $attributes->class([
    'inline-flex items-center rounded-full px-2 py-0.5 text-xs font-semibold',
    match ($color) {
        'success' => 'bg-emerald-100 text-emerald-900',
        'warning' => 'bg-amber-100 text-amber-900',
        'danger' => 'bg-red-100 text-red-800',
        'info' => 'bg-blue-100 text-blue-800',
        default => 'bg-slate-50 text-slate-500 border border-slate-200',
    },
]) }}>{{ $slot }}</span>
