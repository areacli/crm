<x-filament-panels::page>
    @if (auth()->user()->mustChangePassword())
        <x-filament::section :compact="true">
            Você entrou com uma senha temporária. Defina a sua senha para continuar.
        </x-filament::section>
    @endif

    <form wire:submit="save">
        {{ $this->form }}

        <div class="mt-4">
            <x-filament::button type="submit">Salvar a nova senha</x-filament::button>
        </div>
    </form>
</x-filament-panels::page>
