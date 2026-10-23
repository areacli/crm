<?php

namespace App\Livewire\Payments;

use App\Livewire\Imports\Show as ImportsShow;

/** Resultado da importação de pagamentos ou de estornos. */
final class Show extends ImportsShow
{
    protected string $resultView = 'livewire.payments._result';
}
