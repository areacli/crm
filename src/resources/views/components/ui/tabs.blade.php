@props(['tabs'])
{{-- Abas por assunto (P21): cada aba é uma página com endereço próprio. $tabs = [['label' =>, 'route' =>], ...] --}}
<nav class="flex flex-wrap gap-1 border-b border-slate-200" aria-label="Abas">
    @foreach ($tabs as $tab)
        <a href="{{ route($tab['route']) }}" wire:navigate @class([
            '-mb-px rounded-t-md border-b-4 px-4 py-2 text-sm font-semibold',
            'border-blue-600 bg-white text-slate-900' => request()->routeIs($tab['route']),
            'border-transparent text-slate-500 hover:text-blue-700' => ! request()->routeIs($tab['route']),
        ]) @if (request()->routeIs($tab['route'])) aria-current="page" @endif>{{ $tab['label'] }}</a>
    @endforeach
</nav>
