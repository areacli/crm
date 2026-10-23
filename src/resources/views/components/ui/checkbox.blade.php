@props(['label'])
<label class="inline-flex items-center gap-2 text-ink">
    <input type="checkbox" {{ $attributes->class('h-4 w-4 rounded border-line-strong text-ink') }}>
    <span>{{ $label }}</span>
</label>
