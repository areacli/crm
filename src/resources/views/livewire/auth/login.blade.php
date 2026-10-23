<x-ui.card title="Entrar" description="Use o e-mail e a senha do seu usuário.">
    <form wire:submit="login" class="space-y-4">
        <x-ui.field label="E-mail" name="email" required>
            <x-ui.input type="email" id="email" wire:model="email" autocomplete="username" autofocus />
        </x-ui.field>
        <x-ui.field label="Senha" name="password" required>
            <x-ui.input type="password" id="password" wire:model="password" autocomplete="current-password" />
        </x-ui.field>
        <x-ui.checkbox wire:model="remember" label="Manter-me conectado neste navegador" />
        <x-ui.button type="submit" class="w-full">Entrar</x-ui.button>
    </form>
</x-ui.card>
