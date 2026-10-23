<?php

use App\Http\Middleware\EnforceSessionLimits;
use App\Http\Middleware\RequirePasswordChange;
use App\Livewire\Access\Profiles;
use App\Livewire\Access\Users;
use App\Livewire\Auth\ChangePassword;
use App\Livewire\Auth\Login;
use App\Livewire\Contacts;
use App\Livewire\Customers;
use App\Livewire\Imports;
use App\Livewire\Payments;
use App\Livewire\Settings;
use App\Livewire\Summary;
use App\Support\Navigation;
use Illuminate\Http\Request;
use Illuminate\Session\Middleware\AuthenticateSession;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Route;

// Telas do CRM: componentes Livewire de página inteira (decisão 0015). Os endereços seguem os padrões de interface (T1 a T6).
Route::middleware(['web'])->group(function () {
    Route::get('/login', Login::class)->name('login')->middleware('guest');

    Route::post('/logout', function (Request $request) {
        Auth::logout();
        $request->session()->invalidate();
        $request->session()->regenerateToken();

        return redirect()->route('login');
    })->name('logout');

    // AuthenticateSession: trocar a senha encerra as outras sessões do usuário (R39).
    Route::middleware(['auth', AuthenticateSession::class, EnforceSessionLimits::class, RequirePasswordChange::class])->group(function () {
        Route::get('/', Summary::class)->name('summary');

        Route::get('/clientes', Customers\Index::class)->name('customers.index');
        Route::get('/clientes/{customer}', Customers\Show::class)->name('customers.show');
        Route::get('/acionamentos', Contacts\Index::class)->name('contacts.index');

        Route::get('/importar', Imports\Create::class)->name('imports.create');
        Route::get('/importacoes', Imports\Index::class)->name('imports.index');
        Route::get('/importacoes/{import}', Imports\Show::class)->name('imports.show');

        Route::get('/importar-pagamentos', Payments\Upload::class)->defaults('kind', 'payments')->name('payments.create');
        Route::get('/importar-estornos', Payments\Upload::class)->defaults('kind', 'reversals')->name('reversals.create');
        Route::get('/pagamentos', Payments\Index::class)->name('payments.index');
        Route::get('/pagamentos/{import}', Payments\Show::class)->name('payments.show');

        // Configuração (P21): uma entrada e uma aba por assunto, cada uma com a própria permissão; a entrada abre a primeira.
        Route::get('/configuracao', function () {
            $route = Navigation::firstSettingsTab(Auth::user());
            abort_if($route === null, 403);

            return redirect()->route($route);
        })->name('settings');
        Route::get('/configuracao/carteira', Settings\Portfolio::class)->name('settings.portfolio');
        Route::get('/configuracao/canais', Settings\Channels::class)->name('settings.channels');
        Route::get('/configuracao/pagamentos', Settings\PaymentPolicies::class)->name('settings.payments');
        Route::get('/configuracao/acionamentos', Settings\ContactResults::class)->name('settings.contacts');

        Route::get('/usuarios', Users::class)->name('users.index');
        Route::get('/perfis', Profiles\Index::class)->name('profiles.index');
        Route::get('/perfis/novo', Profiles\Form::class)->name('profiles.create');
        Route::get('/perfis/{profile}/editar', Profiles\Form::class)->name('profiles.edit');

        Route::get('/senha', ChangePassword::class)->name('password');
    });
});
