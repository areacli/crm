<?php

use App\Demo\DemoMode;
use App\Enums\ImportStatus;
use App\Enums\Permission;
use App\Filament\Pages\ChangePassword;
use App\Filament\Pages\ImportPayments;
use App\Filament\Pages\ImportPortfolio;
use App\Import\ImportService;
use App\Models\Customer;
use App\Models\Import;
use App\Models\Payment;
use App\Models\User;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;

function demoOn(int $customers = 20): void
{
    config(['crm.demo.enabled' => true, 'crm.demo.domain' => 'demo.crm.areacli.com', 'crm.demo.customers' => $customers, 'crm.demo.tenant' => 'Escola Alfa']);
}

it('recusa recriar fora do modo de demonstração', function () {
    $this->artisan('crm:demo-reset')->assertFailed();
    expect(Customer::count())->toBe(0);
});

it('recria a demonstração: usuários públicos, carteira, recebimentos e perfil sem gestão de acessos', function () {
    demoOn();
    $this->artisan('crm:demo-reset')->assertSuccessful();

    $gestor = User::where('email', 'gestor@demo.crm.areacli.com')->firstOrFail();
    $operador = User::where('email', 'operador@demo.crm.areacli.com')->firstOrFail();
    expect(Customer::count())->toBe(20)->and(Payment::count())->toBeGreaterThan(10)
        ->and($gestor->hasAnyPermission(Permission::ConfirmPayments))->toBeTrue()
        ->and($gestor->hasAnyPermission(Permission::ManageUsers))->toBeFalse()
        ->and($gestor->hasAnyPermission(Permission::ManageProfiles))->toBeFalse()
        ->and($operador->hasAnyPermission(Permission::UploadImports))->toBeFalse();

    // Uma segunda recriação apaga e refaz tudo, e restaura a senha pública.
    $gestor->forceFill(['password' => 'trocada-por-alguem-123', 'active' => false])->save();
    $this->artisan('crm:demo-reset')->assertSuccessful();
    $gestor->refresh();
    expect(Customer::count())->toBe(20)->and($gestor->active)->toBeTrue()
        ->and(Hash::check('demonstracao-gestor', $gestor->password))->toBeTrue();
});

it('ninguém troca a senha dos usuários públicos', function () {
    demoOn();
    $this->artisan('crm:demo-reset')->assertSuccessful();
    $gestor = User::where('email', 'gestor@demo.crm.areacli.com')->first();

    $this->actingAs($gestor)->get(ChangePassword::getUrl())->assertForbidden();
    expect(DemoMode::isPublicUser($gestor))->toBeTrue();
});

it('troca o arquivo enviado por um fictício, sem ler o do visitante', function () {
    demoOn(40);
    $this->artisan('crm:demo-reset')->assertSuccessful();
    // A importação conferida que a recriação deixa pendente ocupa o credor (R10): descarta para testar os envios.
    $pending = Import::where('status', ImportStatus::Checked)->first();
    app(ImportService::class)->discard($pending);
    $gestor = User::where('email', 'gestor@demo.crm.areacli.com')->first();
    $secret = UploadedFile::fake()->createWithContent('meu-arquivo-real.csv', "documento;nome\n999;DADO REAL QUE NAO PODE SER LIDO\n");

    Livewire::actingAs($gestor)->test(ImportPortfolio::class)
        ->fillForm(['mode' => 'incremental', 'file' => $secret])->call('send');
    $import = Import::where('kind', 'portfolio')->latest('id')->first();
    expect($import->original_name)->toBe('arquivo-de-demonstracao.csv')->and($import->status)->toBe(ImportStatus::Checked)
        ->and($import->rejections()->count())->toBe(0)->and($import->summary['valid'])->toBe(400);
    app(ImportService::class)->discard($import);

    $secret2 = UploadedFile::fake()->createWithContent('pagamentos-reais.csv', "canal;identificador\nX;Y\n");
    Livewire::actingAs($gestor)->test(ImportPayments::class)->fillForm(['file' => $secret2])->call('send');
    $payments = Import::where('kind', 'payments')->latest('id')->first();
    expect($payments->original_name)->toBe('arquivo-de-demonstracao.csv')->and($payments->summary['valid'])->toBe(31);
});
