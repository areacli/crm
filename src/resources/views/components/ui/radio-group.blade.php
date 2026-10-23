@props(['options', 'legend' => null, 'name' => null])
{{-- Grupo de opções excludentes. O wire:model vai em cada botão; `options` é valor => rótulo. --}}
<fieldset class="space-y-2">
    @if ($legend)<legend class="text-sm font-semibold text-slate-900">{{ $legend }}</legend>@endif
    @foreach ($options as $value => $label)
        <label class="flex items-start gap-2 text-slate-900">
            <input type="radio" value="{{ $value }}" name="{{ $name ?? $attributes->wire('model')->value() }}" {{ $attributes->class('mt-1 h-4 w-4 border-slate-300 text-slate-900') }}>
            <span>{{ $label }}</span>
        </label>
    @endforeach
</fieldset>
