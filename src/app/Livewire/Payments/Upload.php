<?php

namespace App\Livewire\Payments;

use App\Demo\DemoFiles;
use App\Demo\DemoMode;
use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Livewire\Concerns\Toasts;
use App\Models\Import;
use App\Models\Tenant;
use App\Payments\PaymentColumns;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Component;
use Livewire\WithFileUploads;
use Symfony\Component\HttpFoundation\StreamedResponse;

/** Envio da planilha de pagamentos ou de estornos (R47, R48, R60): escolhe o credor e o arquivo; a conferência roda em segundo plano. */
#[Layout('layouts.app')]
final class Upload extends Component
{
    use Toasts, WithFileUploads;

    /** 'payments' ou 'reversals': as duas telas só mudam o tipo, as colunas e os textos. */
    public string $kind = 'payments';

    public string $tenantId = '';

    public $file;

    public function mount(string $kind = 'payments'): void
    {
        abort_unless(in_array($kind, ['payments', 'reversals'], true), 404);
        $this->kind = $kind;
        Gate::authorize('createPayments', Import::class);
        $tenants = $this->tenants();
        $this->tenantId = $tenants->count() === 1 ? (string) $tenants->first()->id : '';
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->whereIn('id', Auth::user()->tenantIdsWith(Permission::UploadPayments) ?: [0])->orderBy('name')->get();
    }

    public function template(): StreamedResponse
    {
        return response()->streamDownload(fn () => print (PaymentColumns::templateCsv($this->kind)), $this->kind === 'payments' ? 'planilha-modelo-pagamentos.csv' : 'planilha-modelo-estornos.csv', ['Content-Type' => 'text/csv; charset=UTF-8']);
    }

    public function send()
    {
        $this->validate(['tenantId' => ['required'], 'file' => ['required', 'file', 'max:51200']], [], ['tenantId' => 'credor', 'file' => 'arquivo']);

        $tenant = Tenant::findOrFail($this->tenantId);
        Gate::authorize('uploadPayments', [Import::class, $tenant]);

        // Na demonstração, o arquivo do visitante é descartado sem ser lido e trocado por um arquivo fictício da carteira do dia.
        $source = $this->file->getRealPath();
        $original = $this->file->getClientOriginalName();
        if (DemoMode::enabled()) {
            $channel = $tenant->paymentChannels()->where('active', true)->orderBy('id')->value('code') ?? '';
            $source = $this->kind === 'reversals' ? DemoFiles::reversals($tenant) : DemoFiles::payments($tenant, $channel);
            $original = DemoFiles::NAME;
        }

        try {
            $import = app(ImportService::class)->start($tenant, Auth::user(), $source, ImportMode::Incremental, $original, $this->kind);
        } catch (ImportRefused $e) {
            $this->toastError('Não foi possível iniciar a importação: '.$e->getMessage().'.');

            return;
        } finally {
            $this->file?->delete();
            if (DemoMode::enabled()) {
                @unlink($source);
            }
        }

        return $this->redirectRoute('payments.show', $import->id, navigate: true);
    }

    public function render()
    {
        $title = $this->kind === 'reversals' ? 'Importar estornos' : 'Importar pagamentos';

        return view('livewire.payments.upload', [
            'tenants' => $this->tenants(), 'columns' => PaymentColumns::for($this->kind), 'demo' => DemoMode::enabled(), 'heading' => $title,
        ])->title($title);
    }
}
