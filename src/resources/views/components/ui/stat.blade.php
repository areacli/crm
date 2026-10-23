@props(['label', 'value', 'hint' => null, 'small' => false])
<div class="min-w-0">
    <dt class="text-sm text-slate-500">{{ $label }}</dt>
    <dd @class(['break-words font-bold text-slate-900', 'text-xl' => ! $small, 'text-base' => $small])>{{ $value }}</dd>
    @if ($hint)<dd class="text-sm text-slate-500">{{ $hint }}</dd>@endif
</div>
