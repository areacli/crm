<?php

use App\Livewire\Auth\Login;
use App\Models\User;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant, 'joana.souza@exemplo.com.br');
    $this->user->update(['password' => 'cobranca-sem-pressa']);
});

function attemptLogin(string $email, string $password)
{
    return Livewire::test(Login::class)
        ->set('email', $email)
        ->set('password', $password)
        ->call('login');
}

// R24: toda tela exige login; depois de entrar, volta para onde estava.
it('manda quem não tem sessão para a tela de entrada', function () {
    $this->get('/')->assertRedirect('/login');
});

it('entra com e-mail e senha certos', function () {
    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa')->assertHasNoErrors();

    $this->assertAuthenticatedAs($this->user->fresh());
    expect(DB::table('access_events')->where('event', 'login')->count())->toBe(1);
});

// R27: mensagem igual para usuário inexistente, senha errada e bloqueio.
it('dá a mesma mensagem para usuário inexistente e senha errada', function () {
    $a = attemptLogin('ninguem@exemplo.com.br', 'qualquer-senha-longa');
    $b = attemptLogin('joana.souza@exemplo.com.br', 'senha-errada-longa');

    $a->assertHasErrors(['email']);
    $b->assertHasErrors(['email']);
    expect($a->errors()->get('email'))->toEqual(['Essas credenciais não correspondem aos nossos registros.']);
    expect($a->errors()->get('email'))->toEqual($b->errors()->get('email'));
    $this->assertGuest();
});

// R27: 5 erros seguidos bloqueiam por 15 minutos, inclusive para a senha certa.
it('bloqueia por 15 minutos depois de 5 erros seguidos', function () {
    $this->travelTo(now()->setTime(10, 0));
    foreach (range(1, 5) as $i) {
        attemptLogin('joana.souza@exemplo.com.br', 'senha-errada-'.$i);
    }

    expect($this->user->fresh()->locked_until)->not->toBeNull();

    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa')->assertHasErrors(['email']);
    $this->assertGuest();

    $this->travelTo($this->user->fresh()->locked_until->addMinute());
    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa')->assertHasNoErrors();
    $this->assertAuthenticated();
});

it('zera a contagem de erros com um login certo', function () {
    foreach (range(1, 4) as $i) {
        attemptLogin('joana.souza@exemplo.com.br', 'senha-errada-'.$i);
    }
    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa');

    expect($this->user->fresh()->failed_attempts)->toBe(0);
});

// R25: usuário desativado não entra, e a sessão aberta dele deixa de valer na próxima ação.
it('recusa o login do usuário desativado', function () {
    $this->user->update(['active' => false]);

    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa')->assertHasErrors(['email']);
    $this->assertGuest();
});

it('derruba a sessão aberta quando o administrador desativa o usuário', function () {
    $this->actingAs($this->user)->get('/')->assertOk();

    $this->user->update(['active' => false]);

    $this->get('/')->assertRedirect('/login');
    $this->assertGuest();
});

// Usuário sem nenhum vínculo ativo não entra (MT-2).
it('recusa o usuário sem vínculo ativo com um credor', function () {
    $this->user->memberships()->update(['active' => false]);

    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa')->assertHasErrors(['email']);
});

// R28: a sessão vale no máximo 8 horas desde o login.
it('encerra a sessão 8 horas depois do login', function () {
    $this->travelTo(now()->setTime(8, 0));
    attemptLogin('joana.souza@exemplo.com.br', 'cobranca-sem-pressa');

    $this->travel(7)->hours();
    $this->get('/')->assertOk();

    $this->travel(2)->hours();
    $this->get('/')->assertRedirect('/login');
});

// R29: entradas, saídas e recusas ficam registradas.
it('registra recusa e bloqueio nos eventos de acesso', function () {
    attemptLogin('joana.souza@exemplo.com.br', 'errada-errada-errada');

    expect(DB::table('access_events')->where('event', 'login_refused')->where('user_id', $this->user->id)->exists())->toBeTrue();
});

// R26 e R25: o comando do administrador aplica a regra de senha.
it('cria o usuário pelo comando e recusa senha só numérica', function () {
    $this->artisan('crm:user', ['action' => 'create', 'email' => 'novo@exemplo.com.br', '--tenant' => 'Escola Alfa', '--password' => '123456789012'])
        ->expectsOutput('A senha não pode ter só números.')->assertFailed();
    expect(User::where('email', 'novo@exemplo.com.br')->exists())->toBeFalse();

    $this->artisan('crm:user', ['action' => 'create', 'email' => 'novo@exemplo.com.br', '--tenant' => 'Escola Alfa', '--password' => 'cobranca-sem-pressa'])->assertSuccessful();
    expect(Hash::check('cobranca-sem-pressa', User::where('email', 'novo@exemplo.com.br')->first()->password))->toBeTrue();
});

it('recusa senha comum ou parecida com o usuário', function (string $password, string $message) {
    $this->artisan('crm:user', ['action' => 'create', 'email' => 'joana.nova@exemplo.com.br', '--tenant' => 'Escola Alfa', '--password' => $password])
        ->expectsOutput($message)->assertFailed();
})->with([
    ['password1234', 'Senha muito comum.'],
    ['joana.nova1xx', 'A senha é parecida com o usuário.'],
    ['curta', 'A senha precisa ter no mínimo 12 caracteres.'],
]);

it('desativa e reativa pelo comando', function () {
    $this->artisan('crm:user', ['action' => 'deactivate', 'email' => 'joana.souza@exemplo.com.br'])->assertSuccessful();
    expect($this->user->fresh()->active)->toBeFalse();

    $this->artisan('crm:user', ['action' => 'reactivate', 'email' => 'joana.souza@exemplo.com.br'])->assertSuccessful();
    expect($this->user->fresh()->active)->toBeTrue()
        ->and(DB::table('access_events')->whereIn('event', ['admin_user_deactivated', 'admin_user_reactivated'])->count())->toBe(2);
});

it('não recusa a senha por conter um começo de e-mail muito curto', function () {
    $this->artisan('crm:user', ['action' => 'create', 'email' => 'v5@exemplo.com.br', '--tenant' => 'Escola Alfa', '--password' => 'v5-teste-longa-senha'])->assertSuccessful();
});
