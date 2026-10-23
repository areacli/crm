<?php

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\CsvColumns;
use App\Import\CsvFile;
use App\Import\ImportService;
use App\Jobs\CheckImport;
use App\Livewire\Imports\Create as ImportPortfolio;
use App\Livewire\Imports\Index as ListImports;
use App\Livewire\Imports\Show as ViewImport;
use App\Models\Bill;
use App\Models\Import;
use App\Models\Profile;
use Illuminate\Http\UploadedFile;
use Illuminate\Support\Facades\Storage;
use Livewire\Livewire;

beforeEach(function () {
    Storage::fake('local');
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->actingAs($this->user);
});

function csvUpload(array $lines): UploadedFile
{
    return UploadedFile::fake()->createWithContent('carteira.csv',
        "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n".implode("\n", $lines)."\n");
}

it('envia a planilha pela tela, confere e mostra o resultado', function () {
    Livewire::test(ImportPortfolio::class)
        ->set('mode', ImportMode::Incremental->value)
        ->set('file', csvUpload([
            '529.982.247-25;Maria da Silva;;;CT-1;NF-1;10/09/2026;100,00;',
            '111.111.111-11;Fulano;;;;NF-2;10/09/2026;100,00;',
        ]))
        ->call('send')
        ->assertHasNoErrors()
        ->assertRedirect();

    $import = Import::firstOrFail();
    expect($import->status)->toBe(ImportStatus::Checked)->and($import->summary['valid'])->toBe(1);

    Livewire::test(ViewImport::class, ['import' => $import])
        ->assertSee('Conferência')
        ->assertSee('CPF inválido')
        ->assertSee('Confirmar importação');
});

it('confirma pela tela e grava a carteira', function () {
    $import = app(ImportService::class)->start($this->tenant, $this->user, portfolioCsv(['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']), ImportMode::Incremental);

    Livewire::test(ViewImport::class, ['import' => $import])
        ->call('confirmImport');

    expect(Bill::count())->toBe(1)->and($import->refresh()->status)->toBe(ImportStatus::Confirmed);
});

it('descarta pela tela sem gravar nada', function () {
    $import = app(ImportService::class)->start($this->tenant, $this->user, portfolioCsv(['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']), ImportMode::Incremental);

    Livewire::test(ViewImport::class, ['import' => $import])->call('discard');

    expect(Bill::count())->toBe(0)->and($import->refresh()->status)->toBe(ImportStatus::Discarded);
});

it('mostra no resultado do batimento quantos títulos serão retirados', function () {
    makeCustomerWithBills($this->tenant, '52998224725', 'Maria', ['A' => ['2026-09-10', 10000], 'C' => ['2026-09-10', 30000]]);
    $import = app(ImportService::class)->start($this->tenant, $this->user, portfolioCsv(['529.982.247-25;Maria;;;;B;10/09/2026;100,00;']), ImportMode::FullSync);

    Livewire::test(ViewImport::class, ['import' => $import])->assertSee('Serão retirados 2 títulos, R$ 400,00.');
});

it('lista as importações do credor e esconde as de outro credor', function () {
    app(ImportService::class)->start($this->tenant, $this->user, portfolioCsv(['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']), ImportMode::Incremental);
    $beta = makeTenant('Clínica Beta');
    $betaUser = makeUser($beta, 'beta@exemplo.com.br');
    app(ImportService::class)->start($beta, $betaUser, portfolioCsv(['529.982.247-25;Maria;;;;NF-9;10/09/2026;100,00;']), ImportMode::Incremental);

    Livewire::test(ListImports::class)->assertViewHas('rows', fn ($rows) => $rows->total() === 1);
});

// Permissão 3: quem só envia (2) não vê o botão de confirmar.
it('não oferece confirmar a quem só pode enviar', function () {
    $profile = Profile::factory()->create(['tenant_id' => $this->tenant->id, 'name' => 'Só envia', 'permissions' => ['view_portfolio', 'upload_imports']]);
    $sender = makeUser($this->tenant, 'envia@exemplo.com.br');
    $sender->memberships()->update(['profile_id' => $profile->id]);
    $import = app(ImportService::class)->start($this->tenant, $sender, portfolioCsv(['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']), ImportMode::Incremental);

    $this->actingAs($sender->fresh());
    Livewire::test(ViewImport::class, ['import' => $import])->assertDontSee('Confirmar importação');
});

it('mostra as colunas e oferece a planilha-modelo, que passa na conferência sem recusa (R44)', function () {
    $tenant = makeTenant();
    $ana = makeUser($tenant, 'ana@exemplo.com.br');

    Livewire::actingAs($ana)->test(ImportPortfolio::class)
        ->assertSee('Colunas da planilha')->assertSee('vencimento')->assertSee('dd/mm/aaaa')
        ->call('template')->assertFileDownloaded('planilha-modelo-carteira.csv');

    $names = array_column(CsvColumns::all(), 'name');
    expect($names)->toEqualCanonicalizing([...CsvFile::REQUIRED, ...CsvFile::OPTIONAL]);

    $path = tempnam(sys_get_temp_dir(), 'modelo');
    file_put_contents($path, CsvColumns::templateCsv());
    $import = app(ImportService::class)->start($tenant, $ana, $path, ImportMode::Incremental, 'modelo.csv');
    app()->call([new CheckImport($import), 'handle']);
    $import->refresh();
    expect($import->summary['valid'])->toBe(3)->and($import->summary['rejected'])->toBe(0);
});
