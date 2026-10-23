@props(['tabs'])
{{-- Abas por assunto (P21): cada aba é uma página com endereço próprio. $tabs = [['label' =>, 'route' =>], ...] --}}
<nav class="flex flex-wrap gap-1 border-b border-line" aria-label="Abas">
    @foreach ($tabs as $tab)
        <a href="{{ route($tab['route']) }}" wire:navigate @class([
            '-mb-px rounded-t-md border-b-4 px-4 py-2 text-sm font-semibold',
            'border-brand-blue bg-white text-ink' => request()->routeIs($tab['route']),
            'border-transparent text-ink-soft hover:text-brand-blue-dark' => ! request()->routeIs($tab['route']),
        ]) @if (request()->routeIs($tab['route'])) aria-current="page" @endif>{{ $tab['label'] }}</a>
    @endforeach
</nav>
