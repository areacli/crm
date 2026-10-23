@php
    use App\Enums\ImportStatus;
    use App\Support\Money;

    $summary = $import->summary ?? [];
    $effect = $summary['effect'] ?? [];
    $reversals = $import->kind === 'reversals';
    $inProgress = $import->status->isInProgress() && $import->status !== ImportStatus::Checked;
    $rejections = $import->rejections()->orderBy('line')->limit(200)->get();
    $n = fn ($v) => number_format((int) $v, 0, ',', '.');
@endphp

<div class="space-y-6" @if ($inProgress) wire:poll.3s @endif>
    <x-ui.card>
        <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
            <div><dt class="text-sm text-slate-500">Situação</dt><dd class="font-semibold">{{ $import->status->getLabel() }}</dd></div>
            <div><dt class="text-sm text-slate-500">Tipo</dt><dd class="font-semibold">{{ $reversals ? 'Estornos' : 'Pagamentos' }}</dd></div>
            <div><dt class="text-sm text-slate-500">Arquivo</dt><dd class="font-semibold break-all">{{ $import->original_name }}</dd></div>
            <div><dt class="text-sm text-slate-500">Credor</dt><dd class="font-semibold">{{ $import->tenant->name }}</dd></div>
        </dl>
    </x-ui.card>

    @if ($inProgress)
        <x-ui.card title="Andamento">
            <div class="h-3 w-full overflow-hidden rounded bg-slate-200" role="progressbar" aria-valuenow="{{ $import->progress_percent }}" aria-valuemin="0" aria-valuemax="100">
                <div class="h-3 rounded bg-blue-600" style="width: {{ $import->progress_percent }}%"></div>
            </div>
            <p class="mt-2 text-sm text-slate-600">{{ $import->progress_percent }}% — {{ $import->progress_label ?? 'Aguardando' }}. Você pode sair desta tela e voltar: a importação continua.</p>
        </x-ui.card>
    @endif

    @if ($import->failure_reason)
        <x-ui.card title="{{ $import->status === ImportStatus::Failed ? 'A importação falhou' : 'Arquivo recusado' }}">
            <p class="text-sm">{{ ucfirst($import->failure_reason) }}. @if ($import->status === ImportStatus::Failed) Nada foi gravado. Tente de novo. @endif</p>
        </x-ui.card>
    @endif

    @if ($summary)
        <x-ui.card title="{{ $import->status === ImportStatus::Confirmed ? 'Resultado' : 'Conferência' }}">
            <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
                <div><dt class="text-sm text-slate-500">Linhas válidas</dt><dd class="text-lg font-semibold">{{ $n($summary['valid'] ?? 0) }}</dd></div>
                <div><dt class="text-sm text-slate-500">Valor das válidas</dt><dd class="text-lg font-semibold">R$ {{ Money::format((int) ($summary['amount_cents'] ?? 0)) }}</dd></div>
                <div><dt class="text-sm text-slate-500">Já registradas, ignoradas</dt><dd class="text-lg font-semibold">{{ $n($summary['ignored'] ?? 0) }}</dd></div>
                <div><dt class="text-sm text-slate-500">Recusadas</dt><dd class="text-lg font-semibold">{{ $n($summary['rejected'] ?? 0) }}</dd></div>
            </dl>
            <ul class="mt-4 list-disc space-y-1 ps-5 text-sm">
                @if ($reversals)
                    <li>{{ $n($effect['reopened'] ?? 0) }} títulos voltam à cobrança.</li>
                    <li>{{ $n($effect['credit_reduced'] ?? 0) }} créditos reduzidos (R$ {{ Money::format((int) ($effect['from_credit_cents'] ?? 0)) }}); R$ {{ Money::format((int) ($effect['from_bill_cents'] ?? 0)) }} saem dos títulos.</li>
                    <li>{{ $n($effect['pending_reduced'] ?? 0) }} pagamentos pendentes afetados.</li>
                @else
                    <li>{{ $n($effect['settled'] ?? 0) }} títulos quitados, {{ $n($effect['partial'] ?? 0) }} baixas parciais (R$ {{ Money::format((int) ($effect['applied_cents'] ?? 0)) }} aplicados).</li>
                    <li>{{ $n($effect['credits'] ?? 0) }} créditos gerados (R$ {{ Money::format((int) ($effect['credit_cents'] ?? 0)) }}).</li>
                    <li>{{ $n($effect['pending_new'] ?? 0) }} pagamentos pendentes novos (R$ {{ Money::format((int) ($effect['pending_cents'] ?? 0)) }}), {{ $n($effect['pending_applied'] ?? 0) }} pendentes aplicados agora.</li>
                @endif
                @if (! empty($summary['ignored_columns']))
                    <li>Colunas ignoradas: {{ implode(', ', $summary['ignored_columns']) }}.</li>
                @endif
                @if (($summary['blank_lines'] ?? 0) > 0)
                    <li>{{ $n($summary['blank_lines']) }} linhas em branco ignoradas.</li>
                @endif
            </ul>
        </x-ui.card>
    @endif

    @if ($rejections->isNotEmpty())
        <x-ui.card title="Linhas recusadas" :description="($summary['rejected'] ?? 0) > 200 ? 'Mostrando as 200 primeiras.' : null">
            <table class="w-full text-sm">
                <thead><tr class="text-left text-slate-500"><th class="py-1 pe-4">Linha</th><th class="py-1">Motivo</th></tr></thead>
                <tbody>
                    @foreach ($rejections as $rejection)
                        <tr class="border-t border-slate-200"><td class="py-1 pe-4">{{ $rejection->line }}</td><td class="py-1">{{ $rejection->reason }}</td></tr>
                    @endforeach
                </tbody>
            </table>
        </x-ui.card>
    @endif
</div>
