<?php

use App\Models\Profile;
use Illuminate\Support\Facades\Artisan;

/*
| Capturas de tela do incremento 2. Só rodam quando pedidas: CAPTURAS=1 vendor/bin/pest tests/Browser/Capturas
| Os arquivos saem em tests/Browser/Screenshots e são copiados para a pasta de fotos do projeto.
*/
it('captura as telas do incremento 2', function () {
    Artisan::call('crm:demo-data', ['--customers' => 40]);
    $page = visit('/login');
    $page->type('#form\\.email', 'gestor@demo.exemplo.com.br')->type('#form\\.password', 'demonstracao-gestor')->press('Login')
        ->assertSee('Resumo da carteira');

    $page->navigate('/usuarios')->assertSee('Usuários')->screenshot(filename: '01-usuarios');
    $page->click('Novo usuário')->assertSee('Perfil')->screenshot(filename: '02-novo-usuario');
    $page->navigate('/perfis')->assertSee('Perfis')->screenshot(filename: '03-perfis');
    $id = Profile::where('name', 'Operador')->value('id');
    $page->navigate('/perfis/'.$id.'/editar')->assertSee('Permissões')->screenshot(filename: '04-editar-perfil');
    $page->navigate('/senha')->assertSee('Trocar a senha')->screenshot(filename: '05-trocar-senha');
    $page->navigate('/importar')->assertSee('Colunas da planilha')->screenshot(filename: '06-importar-colunas');
})->skip(fn () => ! getenv('CAPTURAS'), 'só roda com CAPTURAS=1');
