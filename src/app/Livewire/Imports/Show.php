<?php

namespace App\Livewire\Imports;

use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Livewire\Concerns\Toasts;
use App\Models\Import;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Component;

/** Resultado de uma importação: andamento, conferência e linhas recusadas, com Confirmar e Descartar (R10, R56, R63). */
#[Layout('layouts.app')]
class Show extends Component
{
    use Toasts;

    public Import $import;

    protected string $resultView = 'livewire.imports._result';

    public function mount(Import $import): void
    {
        Gate::authorize('view', $import);
        $this->import = $import;
    }

    public function confirmImport(): void
    {
        $this->applyTransition(fn (ImportService $s) => $s->confirm($this->import), 'confirm', 'Confirmação iniciada');
    }

    public function discard(): void
    {
        $this->applyTransition(fn (ImportService $s) => $s->discard($this->import), 'discard', 'Importação descartada');
    }

    private function applyTransition(callable $change, string $ability, string $message): void
    {
        Gate::authorize($ability, $this->import);
        try {
            $change(app(ImportService::class));
        } catch (ImportRefused $e) {
            $this->toastError(ucfirst($e->getMessage()).'.');

            return;
        }
        $this->import->refresh();
        $this->toast($message);
    }

    public function render()
    {
        $this->import->refresh();
        $label = $this->import->kind === 'reversals' ? 'Estornos' : ($this->import->kind === 'payments' ? 'Pagamentos' : 'Importação');

        return view('livewire.imports.show', ['import' => $this->import, 'resultView' => $this->resultView])
            ->title(($this->import->kind === 'portfolio' ? 'Importação' : $label.' — importação').' nº '.$this->import->id);
    }
}
