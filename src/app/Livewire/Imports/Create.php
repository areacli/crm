<?php

namespace App\Livewire\Imports;

use App\Demo\DemoFiles;
use App\Demo\DemoMode;
use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Import\CsvColumns;
use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Livewire\Concerns\Toasts;
use App\Models\Import;
use App\Models\Tenant;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;
use Livewire\WithFileUploads;
use Symfony\Component\HttpFoundation\StreamedResponse;

/** Envio da planilha de carteira (R10): escolhe o credor, o modo e o arquivo; a conferência roda em segundo plano. */
#[Layout('layouts.app')]
#[Title('Importar carteira')]
final class Create extends Component
{
    use Toasts, WithFileUploads;

    public string $tenantId = '';

    public string $mode = 'incremental';

    public $file;

    public function mount(): void
    {
        Gate::authorize('create', Import::class);
        $tenants = $this->tenants();
        $this->tenantId = $tenants->count() === 1 ? (string) $tenants->first()->id : '';
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->whereIn('id', Auth::user()->tenantIdsWith(Permission::UploadImports) ?: [0])->orderBy('name')->get();
    }

    /** R44: planilha-modelo no formato aceito, com cabeçalho e três linhas fictícias. */
    public function template(): StreamedResponse
    {
        return response()->streamDownload(fn () => print (CsvColumns::templateCsv()), 'planilha-modelo-carteira.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    public function send()
    {
        $this->validate([
            'tenantId' => ['required'],
            'mode' => ['required', 'in:incremental,full_sync'],
            'file' => ['required', 'file', 'max:51200'],
        ], [], ['tenantId' => 'credor', 'file' => 'arquivo', 'mode' => 'modo']);

        $tenant = Tenant::findOrFail($this->tenantId);
        Gate::authorize('upload', [Import::class, $tenant]);

        // Na demonstração, o arquivo do visitante é descartado sem ser lido e trocado por uma planilha fictícia.
        $source = DemoMode::enabled() ? DemoFiles::portfolio() : $this->file->getRealPath();
        $original = DemoMode::enabled() ? DemoFiles::NAME : $this->file->getClientOriginalName();

        try {
            $import = app(ImportService::class)->start($tenant, Auth::user(), $source, ImportMode::from($this->mode), $original);
        } catch (ImportRefused $e) {
            $this->toastError('Não foi possível iniciar a importação: '.$e->getMessage().'.');

            return;
        } finally {
            $this->file?->delete();
            if (DemoMode::enabled()) {
                @unlink($source);
            }
        }

        return $this->redirectRoute('imports.show', $import->id, navigate: true);
    }

    public function render()
    {
        return view('livewire.imports.create', ['tenants' => $this->tenants(), 'columns' => CsvColumns::all(), 'demo' => DemoMode::enabled()]);
    }
}
