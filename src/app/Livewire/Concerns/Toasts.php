<?php

namespace App\Livewire\Concerns;

/** Avisos curtos na tela (sucesso, erro): disparam o evento `toast`, que o layout mostra. */
trait Toasts
{
    protected function toast(string $message, string $type = 'success', ?string $detail = null, bool $persistent = false): void
    {
        $this->dispatch('toast', message: $message, type: $type, detail: $detail, persistent: $persistent);
    }

    protected function toastError(string $message): void
    {
        $this->toast($message, 'danger');
    }
}
