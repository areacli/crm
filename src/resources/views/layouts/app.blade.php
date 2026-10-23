@php
    use App\Demo\DemoMode;
    use App\Support\Navigation;
    $user = auth()->user();
    $sections = $user ? Navigation::sections($user) : [];
@endphp
<!DOCTYPE html>
<html lang="pt-BR">
<head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1">
    <meta name="robots" content="noindex, nofollow">
    <title>{{ isset($title) ? $title.' · ' : '' }}CRM AreaCli</title>
    @vite(['resources/css/app.css', 'resources/js/app.js'])
</head>
<body class="min-h-screen bg-slate-50">
    @if (DemoMode::enabled())
        <div class="bg-amber-100 px-4 py-2 text-center text-sm text-amber-900" role="note">
            Demonstração: os dados são fictícios e recriados todo dia às {{ config('crm.demo.reset_at') }}, horário de Brasília. Os arquivos que você enviar são descartados sem ser lidos.
        </div>
    @endif

    <div x-data="{ menu: false }" class="min-h-screen">
        <header class="sticky top-0 z-40 flex h-14 items-center justify-between border-b border-slate-200 bg-white px-4">
            <div class="flex items-center gap-3">
                <button type="button" class="rounded p-1 hover:bg-slate-100 lg:hidden" x-on:click="menu = !menu" aria-label="Abrir o menu" x-bind:aria-expanded="menu">
                    <svg class="h-6 w-6" fill="none" viewBox="0 0 24 24" stroke="currentColor" stroke-width="2"><path stroke-linecap="round" d="M4 6h16M4 12h16M4 18h16"/></svg>
                </button>
                <a href="{{ route('summary') }}" class="flex items-center gap-2" wire:navigate>
                    <span class="text-lg font-bold text-slate-900">CRM</span>
                </a>
            </div>
            @auth
                <div class="flex items-center gap-2">
                    <livewire:notifications />
                    <div x-data="{ open: false }" class="relative" x-on:keydown.escape.window="open = false">
                        <button type="button" class="flex items-center gap-2 rounded px-2 py-1 hover:bg-slate-100" x-on:click="open = !open" x-bind:aria-expanded="open" aria-haspopup="true">
                            <span class="flex h-8 w-8 items-center justify-center rounded-full bg-slate-900 text-sm font-bold text-white">{{ mb_strtoupper(mb_substr($user->name, 0, 1)) }}</span>
                            <span class="hidden text-sm font-semibold sm:inline">{{ $user->name }}</span>
                        </button>
                        <div x-show="open" x-cloak x-on:click.outside="open = false" class="absolute right-0 mt-2 w-56 rounded-md border border-slate-200 bg-white py-1 text-slate-900 shadow-lg">
                            <div class="border-b border-slate-200 px-4 py-2 text-sm text-slate-500">{{ $user->email }}</div>
                            @if (! \App\Demo\DemoMode::isPublicUser($user))
                                <a href="{{ route('password') }}" class="block px-4 py-2 text-sm hover:bg-slate-50" wire:navigate>Trocar a senha</a>
                            @endif
                            <form method="POST" action="{{ route('logout') }}">
                                @csrf
                                <button type="submit" class="block w-full px-4 py-2 text-left text-sm hover:bg-slate-50">Sair</button>
                            </form>
                        </div>
                    </div>
                </div>
            @endauth
        </header>

        <div class="flex">
            @auth
                <nav x-bind:class="menu ? 'block' : 'hidden'" class="fixed inset-x-0 top-14 z-30 max-h-[calc(100vh-3.5rem)] overflow-y-auto border-b border-slate-200 bg-white p-3 lg:static lg:block lg:max-h-none lg:w-64 lg:shrink-0 lg:border-b-0 lg:border-r" aria-label="Menu">
                    @foreach ($sections as $section)
                        <div class="mb-3">
                            @if ($section['title'])
                                <p class="px-3 pb-1 text-xs font-semibold uppercase tracking-[0.06em] text-slate-500">{{ $section['title'] }}</p>
                            @endif
                            @foreach ($section['items'] as $item)
                                <a href="{{ route($item['route']) }}" wire:navigate @class([
                                    'block rounded-md px-3 py-2 text-sm font-semibold',
                                    'bg-slate-100 text-slate-900' => request()->is($item['match']),
                                    'text-slate-700 hover:bg-slate-50' => ! request()->is($item['match']),
                                ]) @if (request()->is($item['match'])) aria-current="page" @endif>{{ $item['label'] }}</a>
                            @endforeach
                        </div>
                    @endforeach
                </nav>
            @endauth

            <main class="min-w-0 flex-1 p-4 sm:p-6">
                <div class="mx-auto max-w-7xl space-y-6">
                    {{ $slot }}
                </div>
            </main>
        </div>
    </div>

    @if (session('status'))<div x-data x-init="$dispatch('toast', { message: @js(session('status')), type: 'success' })"></div>@endif

    {{-- Avisos curtos: os componentes disparam o evento "toast" (trait Toasts). --}}
    <div x-data="{
            toasts: [],
            add(d) {
                const t = { id: Date.now() + Math.random(), ...d };
                this.toasts.push(t);
                if (!t.persistent) setTimeout(() => this.remove(t.id), 6000);
            },
            remove(id) { this.toasts = this.toasts.filter(t => t.id !== id); },
        }" x-on:toast.window="add($event.detail)" class="fixed bottom-4 right-4 z-[60] flex w-full max-w-sm flex-col gap-2" aria-live="polite">
        <template x-for="t in toasts" x-bind:key="t.id">
            <div class="rounded-lg border bg-white p-4 shadow-lg" x-bind:class="{ 'border-emerald-500': t.type === 'success', 'border-red-600': t.type === 'danger', 'border-amber-400': t.type === 'warning' }" role="status">
                <div class="flex items-start justify-between gap-3">
                    <div>
                        <p class="font-semibold text-slate-900" x-text="t.message"></p>
                        <p class="mt-1 break-words text-sm text-slate-900" x-show="t.detail" x-text="t.detail"></p>
                    </div>
                    <button type="button" class="text-slate-500 hover:text-slate-900" x-on:click="remove(t.id)" aria-label="Fechar o aviso">✕</button>
                </div>
            </div>
        </template>
    </div>
</body>
</html>
