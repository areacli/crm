@props(['options', 'legend' => null, 'name' => null])
{{-- Grupo de opções excludentes. O wire:model vai em cada botão; `options` é valor => rótulo. --}}
<fieldset class="space-y-2">
    @if ($legend)<legend class="text-sm font-semibold text-ink">{{ $legend }}</legend>@endif
    @foreach ($options as $value => $label)
        <label class="flex items-start gap-2 text-ink">
            <input type="radio" value="{{ $value }}" name="{{ $name ?? $attributes->wire('model')->value() }}" {{ $attributes->class('mt-1 h-4 w-4 border-line-strong text-ink') }}>
            <span>{{ $label }}</span>
        </label>
    @endforeach
</fieldset>
