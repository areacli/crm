@props(['label'])
<label class="inline-flex items-center gap-2 text-slate-900">
    <input type="checkbox" {{ $attributes->class('h-4 w-4 rounded border-slate-300 text-slate-900') }}>
    <span>{{ $label }}</span>
</label>
