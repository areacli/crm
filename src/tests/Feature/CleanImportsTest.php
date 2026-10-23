<?php

use App\Enums\ImportMode;
use App\Enums\ImportStatus;
use App\Import\ImportService;
use App\Models\Import;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Storage;

beforeEach(function () {
    Storage::fake('local');
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->service = app(ImportService::class);
});

function checkedImport($test): Import
{
    return $test->service->start($test->tenant, $test->user, portfolioCsv(['529.982.247-25;Maria;;;;NF-1;10/09/2026;100,00;']), ImportMode::Incremental);
}

// R10: conferência abandonada é descartada depois de 1 hora, sem efeito.
it('descarta a conferência abandonada há mais de 1 hora e libera o credor', function () {
    $import = checkedImport($this);
    $this->travel(61)->minutes();

    $this->artisan('crm:clean-imports')->assertSuccessful();

    expect($import->refresh()->status)->toBe(ImportStatus::Discarded)
        ->and(DB::table('import_rows')->where('import_id', $import->id)->count())->toBe(0)
        ->and($this->service->inProgress($this->tenant))->toBeNull()
        ->and(DB::table('task_runs')->where('task', 'clean-imports')->count())->toBe(1);
});

it('não mexe na conferência com menos de 1 hora', function () {
    $import = checkedImport($this);
    $this->travel(59)->minutes();

    $this->artisan('crm:clean-imports')->assertSuccessful();

    expect($import->refresh()->status)->toBe(ImportStatus::Checked)
        ->and(DB::table('task_runs')->count())->toBe(0);
});

// Domínio, P5: importação presa há mais de 30 minutos passa a "falhou", com o motivo, e libera o credor.
it('marca como falha a importação presa há mais de 30 minutos', function () {
    $import = checkedImport($this);
    $import->update(['status' => ImportStatus::Confirming]);
    $this->travel(31)->minutes();

    $this->artisan('crm:clean-imports')->assertSuccessful();

    expect($import->refresh()->status)->toBe(ImportStatus::Failed)
        ->and($import->failure_reason)->toBe('tempo-limite: 30 minutos sem terminar')
        ->and($this->service->inProgress($this->tenant))->toBeNull();
});

it('não registra execução quando não há o que limpar', function () {
    $this->artisan('crm:clean-imports')->assertSuccessful();

    expect(DB::table('task_runs')->count())->toBe(0);
});
