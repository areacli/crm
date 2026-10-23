<div class="max-w-xl space-y-4">
    <x-ui.page-header title="Trocar a senha" />
    @if ($forced)<x-ui.alert type="warning">Você entrou com uma senha temporária. Defina a sua senha para continuar.</x-ui.alert>@endif
    <x-ui.card>
        <form wire:submit="save" class="space-y-4">
            <x-ui.field label="Senha atual" name="current_password" required><x-ui.input type="password" id="current_password" wire:model="current_password" autocomplete="current-password" /></x-ui.field>
            <x-ui.field label="Nova senha" name="password" required help="Mínimo de 12 caracteres, sem ser comum, só números ou parecida com o seu e-mail."><x-ui.input type="password" id="password" wire:model="password" autocomplete="new-password" /></x-ui.field>
            <x-ui.field label="Repita a nova senha" name="password_confirmation" required><x-ui.input type="password" id="password_confirmation" wire:model="password_confirmation" autocomplete="new-password" /></x-ui.field>
            <x-ui.button type="submit">Salvar a nova senha</x-ui.button>
        </form>
    </x-ui.card>
</div>
