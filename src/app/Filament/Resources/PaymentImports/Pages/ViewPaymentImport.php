<?php

namespace App\Filament\Resources\PaymentImports\Pages;

use App\Filament\Resources\PaymentImports\PaymentImportResource;
use App\Import\ImportRefused;
use App\Import\ImportService;
use Filament\Actions\Action;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;

class ViewPaymentImport extends ViewRecord
{
    protected static string $resource = PaymentImportResource::class;

    public function getTitle(): string
    {
        return ($this->getRecord()->kind === 'reversals' ? 'Estornos' : 'Pagamentos').' — importação nº '.$this->getRecord()->id;
    }

    /** Chamado pelo wire:poll da tela enquanto a importação está em andamento. */
    public function refreshRecord(): void
    {
        $this->getRecord()->refresh();
    }

    protected function getHeaderActions(): array
    {
        return [
            Action::make('confirm')->label('Confirmar importação')->authorize('confirm')
                ->requiresConfirmation()
                ->modalDescription('Aplica tudo numa única operação.')
                ->action(fn () => $this->runTransition(fn (ImportService $s) => $s->confirm($this->getRecord()), 'Confirmação iniciada')),
            Action::make('discard')->label('Descartar')->color('gray')->authorize('discard')
                ->requiresConfirmation()
                ->action(fn () => $this->runTransition(fn (ImportService $s) => $s->discard($this->getRecord()), 'Importação descartada')),
        ];
    }

    private function runTransition(callable $change, string $message): void
    {
        try {
            $change(app(ImportService::class));
        } catch (ImportRefused $e) {
            Notification::make()->title(ucfirst($e->getMessage()).'.')->danger()->send();

            return;
        }
        $this->getRecord()->refresh();
        Notification::make()->title($message)->success()->send();
    }
}
