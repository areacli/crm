<?php

namespace App\Livewire\Payments;

use App\Enums\Permission;
use App\Livewire\Imports\Index as ImportsIndex;

/** Importações de pagamentos e de estornos: histórico, andamento e resultado (R56, R63). */
final class Index extends ImportsIndex
{
    protected array $kinds = ['payments', 'reversals'];

    protected string $title = 'Pagamentos e estornos';

    protected function permissions(): array
    {
        return [Permission::UploadPayments, Permission::ConfirmPayments];
    }

    protected function newRoute(): string
    {
        return 'payments.create';
    }

    protected function showRoute(): string
    {
        return 'payments.show';
    }
}
