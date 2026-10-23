@props(['field' => null, 'sort' => '', 'dir' => 'desc', 'align' => 'left'])
{{-- Cabeçalho de coluna; com `field`, clicar ordena por ela. --}}
<th scope="col" {{ $attributes->class(['whitespace-nowrap bg-slate-50 px-2 py-1.5 font-semibold text-slate-500', 'text-left' => $align === 'left', 'text-right' => $align === 'right']) }}>
    @if ($field)
        <button type="button" wire:click="sortBy('{{ $field }}')" class="inline-flex items-center gap-1 font-semibold hover:text-blue-700">
            {{ $slot }}
            @if ($sort === $field)<span aria-hidden="true">{{ $dir === 'asc' ? '▲' : '▼' }}</span>@endif
        </button>
    @else
        {{ $slot }}
    @endif
</th>
