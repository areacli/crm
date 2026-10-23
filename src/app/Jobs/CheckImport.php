<?php

namespace App\Jobs;

use App\Import\ImportChecker;
use App\Models\Import;
use App\Payments\PaymentImportChecker;
use Illuminate\Contracts\Queue\ShouldQueue;
use Illuminate\Foundation\Queue\Queueable;
use Illuminate\Queue\Attributes\DeleteWhenMissingModels;
use Illuminate\Queue\Attributes\Timeout;
use Illuminate\Queue\Attributes\Tries;

/** Conferência da importação em segundo plano (R10). */
#[Tries(1)]
#[Timeout(600)]
#[DeleteWhenMissingModels]
final class CheckImport implements ShouldQueue
{
    use Queueable;

    public function __construct(public readonly Import $import) {}

    public function handle(ImportChecker $checker, PaymentImportChecker $paymentChecker): void
    {
        $this->import->kind === 'portfolio' ? $checker->run($this->import) : $paymentChecker->run($this->import);
    }
}
