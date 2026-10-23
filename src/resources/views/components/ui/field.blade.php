@props(['label' => null, 'name' => null, 'help' => null, 'required' => false])
{{-- Rótulo, ajuda e erro de validação de um campo. `name` é a chave do erro (por exemplo, "form.email"). --}}
<div {{ $attributes->class('space-y-1') }}>
    @if ($label)
        <label class="block text-sm font-semibold text-ink">{{ $label }}@if ($required)<span class="text-red-600" aria-hidden="true"> *</span>@endif</label>
    @endif
    {{ $slot }}
    @if ($help)
        <p class="text-sm text-ink-soft">{{ $help }}</p>
    @endif
    @if ($name)
        @error($name)<p class="text-sm font-semibold text-red-600" role="alert">{{ $message }}</p>@enderror
    @endif
</div>
