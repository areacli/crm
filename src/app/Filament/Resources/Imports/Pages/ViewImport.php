<?php

namespace App\Filament\Resources\Imports\Pages;

use App\Filament\Resources\Imports\ImportResource;
use App\Import\ImportRefused;
use App\Import\ImportService;
use Filament\Actions\Action;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;

class ViewImport extends ViewRecord
{
    protected static string $resource = ImportResource::class;

    public function getTitle(): string
    {
        return 'Importação nº '.$this->getRecord()->id;
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
                ->modalDescription('Grava as linhas válidas na carteira, numa única operação.')
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
