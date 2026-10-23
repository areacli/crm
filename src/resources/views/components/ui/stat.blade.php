@props(['label', 'value', 'hint' => null, 'small' => false])
<div class="min-w-0">
    <dt class="text-sm text-ink-soft">{{ $label }}</dt>
    <dd @class(['break-words font-bold text-ink', 'text-xl' => ! $small, 'text-base' => $small])>{{ $value }}</dd>
    @if ($hint)<dd class="text-sm text-ink-soft">{{ $hint }}</dd>@endif
</div>
