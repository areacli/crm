<?php

use App\Access\AccessManager;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use Illuminate\Support\Facades\Artisan;

/*
| Critérios de aceite da especificação 02 em navegador real (V2): o gestor cria um operador, entrega a senha
| temporária, o operador define a própria senha e consulta a carteira, mas não importa nem configura.
*/
beforeEach(function () {
    Artisan::call('crm:demo-data', ['--customers' => 20]);
});

it('o gestor cria um operador pela tela e vê a senha temporária uma única vez', function () {
    $page = visit('/login');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira');

    $page->navigate('/usuarios')->assertSee('Usuários')->click('Novo usuário')
        ->type('[id$="email"]', 'joana.souza@credor.example')->type('[id$="name"]', 'Joana Souza')
        ->select('[id$="profile_id"]', (string) Profile::where('name', 'Operador')->value('id'))
        ->click('Enviar')->assertSee('Senha temporária');

    expect(User::where('email', 'joana.souza@credor.example')->first()?->mustChangePassword())->toBeTrue();
});

it('o operador define a própria senha no primeiro acesso e não vê Importar nem Configuração', function () {
    $tenant = Tenant::first();
    $profile = Profile::where('tenant_id', $tenant->id)->where('name', 'Operador')->first();
    [, $password] = app(AccessManager::class)->createUser(User::where('email', 'gestor@demo.exemplo.com.br')->first(), $tenant, 'joana.souza@credor.example', 'Joana Souza', $profile);

    $page = visit('/login');
    $page->type('#form\\.email', 'joana.souza@credor.example')->type('#form\\.password', $password)->press('Login')
        ->assertPathIs('/senha')->assertSee('senha temporária');
    $page->type('#form\\.current_password', $password)->type('#form\\.password', 'senha-nova-bem-longa')
        ->type('#form\\.password_confirmation', 'senha-nova-bem-longa')->press('Salvar a nova senha')
        ->assertSee('Resumo da carteira')->assertDontSee('Importar carteira')->assertDontSee('Configuração');
    $page->navigate('/importar')->assertDontSee('Enviar e conferir');

    expect(User::where('email', 'joana.souza@credor.example')->first()->mustChangePassword())->toBeFalse();
});
