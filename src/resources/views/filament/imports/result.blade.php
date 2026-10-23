@php
    use App\Enums\ImportMode;
    use App\Enums\ImportStatus;
    use App\Support\Money;

    /** @var \App\Models\Import $import */
    $import = $getRecord();
    $summary = $import->summary ?? [];
    $inProgress = $import->status->isInProgress() && $import->status !== ImportStatus::Checked;
    $rejections = $import->rejections()->orderBy('line')->limit(200)->get();
    $rejectedTotal = (int) ($summary['rejected'] ?? 0);
@endphp

<div class="space-y-6" @if ($inProgress) wire:poll.3s="refreshRecord" @endif>
    <x-filament::section :compact="true">
        <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
            <div>
                <dt class="text-sm text-gray-500">Situação</dt>
                <dd class="font-semibold">{{ $import->status->getLabel() }}</dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">Modo</dt>
                <dd class="font-semibold">{{ $import->mode->getLabel() }}</dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">Arquivo</dt>
                <dd class="font-semibold break-all">{{ $import->original_name }}</dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">Credor</dt>
                <dd class="font-semibold">{{ $import->tenant->name }}</dd>
            </div>
        </dl>
    </x-filament::section>

    @if ($inProgress)
        <x-filament::section heading="Andamento" :compact="true">
            <div class="h-3 w-full overflow-hidden rounded bg-gray-200" role="progressbar" aria-valuenow="{{ $import->progress_percent }}" aria-valuemin="0" aria-valuemax="100">
                <div class="h-3 rounded bg-primary-600" style="width: {{ $import->progress_percent }}%"></div>
            </div>
            <p class="mt-2 text-sm text-gray-600">{{ $import->progress_percent }}% — {{ $import->progress_label ?? 'Aguardando' }}. Você pode sair desta tela e voltar: a importação continua.</p>
        </x-filament::section>
    @endif

    @if ($import->failure_reason)
        <x-filament::section heading="{{ $import->status === ImportStatus::Failed ? 'A importação falhou' : 'Arquivo recusado' }}" :compact="true">
            <p class="text-sm">{{ ucfirst($import->failure_reason) }}.
                @if ($import->status === ImportStatus::Failed) Nada foi gravado. Tente de novo. @endif
            </p>
        </x-filament::section>
    @endif

    @if ($summary)
        <x-filament::section heading="{{ $import->status === ImportStatus::Confirmed ? 'Resultado' : 'Conferência' }}" :compact="true">
            <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
                <div><dt class="text-sm text-gray-500">Clientes</dt><dd class="text-lg font-semibold">{{ number_format($summary['customers'] ?? 0, 0, ',', '.') }}</dd></div>
                <div><dt class="text-sm text-gray-500">Títulos válidos</dt><dd class="text-lg font-semibold">{{ number_format($summary['valid'] ?? 0, 0, ',', '.') }}</dd></div>
                <div><dt class="text-sm text-gray-500">Valor dos válidos</dt><dd class="text-lg font-semibold">R$ {{ Money::format((int) ($summary['amount_cents'] ?? 0)) }}</dd></div>
                <div><dt class="text-sm text-gray-500">Recusados</dt><dd class="text-lg font-semibold">{{ number_format($rejectedTotal, 0, ',', '.') }}</dd></div>
            </dl>

            <ul class="mt-4 list-disc space-y-1 ps-5 text-sm">
                <li>{{ number_format($summary['bills_new'] ?? 0, 0, ',', '.') }} títulos novos, {{ number_format($summary['bills_updated'] ?? 0, 0, ',', '.') }} atualizados, {{ number_format($summary['bills_unchanged'] ?? 0, 0, ',', '.') }} sem mudança.</li>
                <li>{{ number_format($summary['customers_new'] ?? 0, 0, ',', '.') }} clientes novos.</li>
                @if (($summary['bills_paid_kept'] ?? 0) > 0)
                    <li>{{ $summary['bills_paid_kept'] }} títulos pagos neste sistema, mantidos como estão.</li>
                @endif
                @if (($summary['bills_reincluded'] ?? 0) > 0)
                    <li>{{ $summary['bills_reincluded'] }} títulos retirados voltam à carteira.</li>
                @endif
                @if ($import->mode === ImportMode::FullSync)
                    <li class="font-semibold">Serão retirados {{ number_format($summary['to_withdraw']['count'] ?? 0, 0, ',', '.') }} títulos, R$ {{ Money::format((int) ($summary['to_withdraw']['amount_cents'] ?? 0)) }}.</li>
                    @if (($summary['kept_by_rejection'] ?? 0) > 0)
                        <li>{{ $summary['kept_by_rejection'] }} títulos mantidos por linha recusada.</li>
                    @endif
                @endif
                @if (($summary['contracts_created_by_omission'] ?? 0) > 0)
                    <li>{{ $summary['contracts_created_by_omission'] }} contratos serão criados por omissão (linhas sem contrato informado).</li>
                @endif
                @if (($summary['contracts_multi_customer'] ?? 0) > 0)
                    <li>{{ $summary['contracts_multi_customer'] }} contratos com mais de um cliente.</li>
                @endif
                @if (($summary['roles_declared'] ?? 0) > 0)
                    <li>{{ number_format($summary['roles_declared'], 0, ',', '.') }} linhas declaram o papel do cliente no contrato.</li>
                @endif
                @if (($summary['blank_lines'] ?? 0) > 0)
                    <li>{{ $summary['blank_lines'] }} linhas em branco ignoradas.</li>
                @endif
                @if (! empty($summary['ignored_columns']))
                    <li>Colunas ignoradas: {{ implode(', ', $summary['ignored_columns']) }}.</li>
                @endif
            </ul>
        </x-filament::section>
    @endif

    @if ($rejections->isNotEmpty())
        <x-filament::section heading="Linhas recusadas" :description="$rejectedTotal > $rejections->count() ? 'Mostrando as primeiras '.$rejections->count().' de '.number_format($rejectedTotal, 0, ',', '.') : null" :compact="true">
            <table class="w-full text-sm">
                <thead><tr class="text-left text-gray-500"><th class="py-1 pe-4">Linha</th><th class="py-1">Motivo</th></tr></thead>
                <tbody>
                    @foreach ($rejections as $rejection)
                        <tr class="border-t border-gray-100 dark:border-white/10">
                            <td class="py-1 pe-4">{{ $rejection->line }}</td>
                            <td class="py-1">{{ ucfirst($rejection->reason) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </x-filament::section>
    @endif
</div>
