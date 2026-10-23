@props(['type' => 'info'])
<div {{ $attributes->class([
    'rounded-md border px-4 py-3 text-sm',
    match ($type) { 'danger' => 'border-red-300 bg-red-50 text-ink', 'warning' => 'border-amber-300 bg-amber-50 text-ink', default => 'border-brand-blue bg-surface text-ink' },
]) }} role="note">{{ $slot }}</div>
