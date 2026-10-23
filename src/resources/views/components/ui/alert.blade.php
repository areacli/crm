@props(['type' => 'info'])
<div {{ $attributes->class([
    'rounded-md border px-4 py-3 text-sm',
    match ($type) { 'danger' => 'border-red-300 bg-red-50 text-slate-900', 'warning' => 'border-amber-300 bg-amber-50 text-slate-900', default => 'border-blue-300 bg-blue-50 text-slate-900' },
]) }} role="note">{{ $slot }}</div>
