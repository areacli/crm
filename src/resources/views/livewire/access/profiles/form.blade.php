<div class="space-y-4">
    <x-ui.page-header :title="$profile ? 'Editar perfil' : 'Novo perfil'" />
    <form wire:submit="save" class="space-y-6">
        <x-ui.card>
            <div class="space-y-4">
                @if ($several && ! $profile)
                    <x-ui.field label="Credor" name="tenantId" required class="max-w-sm"><x-ui.select wire:model="tenantId"><option value="">Escolha</option>@foreach ($tenants as $id => $name)<option value="{{ $id }}">{{ $name }}</option>@endforeach</x-ui.select></x-ui.field>
                @endif
                <x-ui.field label="Nome do perfil" name="name" required class="max-w-md"><x-ui.input wire:model="name" maxlength="60" /></x-ui.field>
                <fieldset>
                    <legend class="mb-2 text-sm font-semibold">Permissões <span class="text-red-600">*</span></legend>
                    <div class="grid gap-2 sm:grid-cols-2">
                        @foreach ($all as $p)
                            <label class="flex items-start gap-2"><input type="checkbox" value="{{ $p->value }}" wire:model="permissions" class="mt-1 h-4 w-4 rounded border-slate-300"><span>{{ $p->number() }}. {{ $p->label() }}</span></label>
                        @endforeach
                    </div>
                    @error('permissions')<p class="mt-1 text-sm font-semibold text-red-600">{{ $message }}</p>@enderror
                </fieldset>
            </div>
        </x-ui.card>
        <div class="flex gap-2">
            <x-ui.button type="submit">Salvar alterações</x-ui.button>
            <x-ui.button variant="secondary" :href="route('profiles.index')" wire:navigate>Cancelar</x-ui.button>
        </div>
    </form>
</div>
