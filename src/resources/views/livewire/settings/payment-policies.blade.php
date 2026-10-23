<div class="space-y-4">
    <x-ui.page-header title="Configuração" />
    <x-ui.tabs :tabs="\App\Support\Navigation::settingsTabs(auth()->user())" />

    <form wire:submit="save" class="space-y-4">
        @if ($tenants->count() > 1)
            <x-ui.field label="Credor" class="max-w-sm"><x-ui.select wire:model.live="tenantId">@foreach ($tenants as $t)<option value="{{ $t->id }}">{{ $t->name }}</option>@endforeach</x-ui.select></x-ui.field>
        @endif
        @foreach ($groups as $field => [$title, $options])
            <x-ui.card :title="$title"><x-ui.radio-group wire:model="{{ $field }}" :options="$options" /></x-ui.card>
        @endforeach
        <x-ui.button type="submit">Salvar</x-ui.button>
    </form>
</div>
