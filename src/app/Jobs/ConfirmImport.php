<?php

namespace App\Jobs;

use App\Import\ImportConfirmer;
use App\Models\Import;
use App\Payments\PaymentImportConfirmer;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\Attributes\DeleteWhenMissingModels;
use Illuminate\Queue\Attributes\Timeout;
use Illuminate\Queue\Attributes\Tries;

/** Confirmação da importação em segundo plano: uma transação única (R10). */
#[Tries(1)]
#[Timeout(900)]
#[DeleteWhenMissingModels]
final class ConfirmImport implements ShouldQueue
{
    use Queueable;

    public function __construct(public readonly Import $import) {}

    public function handle(ImportConfirmer $confirmer, PaymentImportConfirmer $paymentConfirmer): void
    {
        $this->import->kind === 'portfolio' ? $confirmer->run($this->import) : $paymentConfirmer->run($this->import);
    }
}
