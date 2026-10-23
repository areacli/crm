@php
    use App\Enums\UpcomingDisplay;
    use App\Support\Money;
    $summaries = $this->summaries();
@endphp

<div class="space-y-4">
    <x-ui.page-header title="Resumo da carteira" />
    @forelse ($summaries as $s)
        <x-ui.card :title="count($summaries) > 1 ? $s['tenant']->name : null">
            <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
                <div>
                    <dt class="text-sm text-ink-soft">Clientes em cobrança</dt>
                    <dd class="text-xl font-bold text-ink">{{ number_format($s['upcoming_display'] === UpcomingDisplay::DetailOnly ? $s['customers_overdue'] : $s['customers'], 0, ',', '.') }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-ink-soft">Títulos</dt>
                    <dd class="text-xl font-bold text-ink">{{ number_format($s['bills'], 0, ',', '.') }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-ink-soft">Vencido</dt>
                    <dd class="text-xl font-bold text-ink">R$ {{ Money::format($s['overdue_cents']) }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-ink-soft">A vencer</dt>
                    <dd class="text-xl font-bold text-ink">
                        @if ($s['upcoming_display'] === UpcomingDisplay::DetailOnly) — @else R$ {{ Money::format($s['upcoming_cents']) }} @endif
                    </dd>
                </div>
            </dl>
            @if ($s['upcoming_display'] === UpcomingDisplay::Summed)
                <p class="mt-3 text-sm text-ink-soft">Em cobrança, somando o a vencer: R$ {{ Money::format($s['overdue_cents'] + $s['upcoming_cents']) }} (vencido R$ {{ Money::format($s['overdue_cents']) }}).</p>
            @endif
        </x-ui.card>

        <x-ui.card title="Recebimentos">
            <dl class="grid grid-cols-1 gap-4 md:grid-cols-4">
                @foreach ($s['recovered'] as $month)
                    <div>
                        <dt class="text-sm text-ink-soft">Recuperado em {{ $month['label'] }}</dt>
                        <dd class="text-xl font-bold text-ink">R$ {{ Money::format($month['total']) }}</dd>
                        @if ($month['methods'] !== [])
                            <dd class="text-sm text-ink-soft">
                                @foreach ($month['methods'] as $method => $cents){{ $method }} R$ {{ Money::format($cents) }}@if (! $loop->last); @endif @endforeach
                            </dd>
                        @endif
                    </div>
                @endforeach
                <div>
                    <dt class="text-sm text-ink-soft">Créditos dos contratos</dt>
                    <dd class="text-xl font-bold text-ink">R$ {{ Money::format($s['credit_cents']) }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-ink-soft">Pagamentos pendentes</dt>
                    <dd class="text-xl font-bold text-ink">{{ number_format($s['pending_count'], 0, ',', '.') }}</dd>
                    <dd class="text-sm text-ink-soft">R$ {{ Money::format($s['pending_cents']) }}</dd>
                </div>
            </dl>
        </x-ui.card>

        <x-ui.card title="Acionamentos">
            <div class="grid gap-6 md:grid-cols-2">
                @foreach ($s['contacts'] as $days => $block)
                    <div>
                        <p class="text-sm text-ink-soft">Últimos {{ $days }} dias</p>
                        <table class="mt-1 w-full text-sm">
                            <thead><tr class="text-left text-ink-soft"><th class="py-1 pe-4"></th><th class="py-1 pe-4 text-end">Acionamentos</th><th class="py-1 text-end">Clientes</th></tr></thead>
                            <tbody>
                                <tr class="border-t border-line font-semibold dark:border-white/10"><td class="py-1 pe-4">Total</td><td class="py-1 pe-4 text-end">{{ number_format($block['total']['attempts'], 0, ',', '.') }}</td><td class="py-1 text-end">{{ number_format($block['total']['customers'], 0, ',', '.') }}</td></tr>
                                @foreach ($block['types'] as $type => $numbers)
                                    <tr class="border-t border-line"><td class="py-1 pe-4">{{ \App\Enums\ContactResultType::from($type)->getLabel() }}</td><td class="py-1 pe-4 text-end">{{ number_format($numbers['attempts'], 0, ',', '.') }}</td><td class="py-1 text-end">{{ number_format($numbers['customers'], 0, ',', '.') }}</td></tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @endforeach
            </div>
        </x-ui.card>

        <div class="grid gap-6 md:grid-cols-2">
            @foreach ([['title' => 'Por cliente', 'help' => 'Cada cliente na faixa do título mais atrasado, com todo o seu vencido.', 'rows' => $s['by_customer'], 'unit' => 'Clientes'],
                       ['title' => 'Por título', 'help' => 'Cada título vencido na faixa do próprio atraso.', 'rows' => $s['by_bill'], 'unit' => 'Títulos']] as $table)
                @php($max = max(1, collect($table['rows'])->max('cents')))
                <x-ui.card :title="'Faixas de atraso — '.$table['title']" :description="$table['help']">
                    <table class="w-full text-sm">
                        <thead>
                            <tr class="text-left text-ink-soft">
                                <th class="py-1 pe-4">Faixa (dias)</th>
                                <th class="py-1 pe-4 text-end">{{ $table['unit'] }}</th>
                                <th class="py-1 text-end">Valor vencido</th>
                                <th class="py-1 ps-4 w-1/3"></th>
                            </tr>
                        </thead>
                        <tbody>
                            @foreach ($table['rows'] as $row)
                                <tr class="border-t border-line">
                                    <td class="py-1 pe-4">{{ $row['label'] }}</td>
                                    <td class="py-1 pe-4 text-end">{{ number_format($row['count'], 0, ',', '.') }}</td>
                                    <td class="py-1 text-end">R$ {{ Money::format($row['cents']) }}</td>
                                    <td class="py-1 ps-4"><div class="h-2 rounded bg-brand-blue" style="width: {{ round(100 * $row['cents'] / $max) }}%"></div></td>
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                </x-ui.card>
            @endforeach
        </div>
    @empty
        <x-ui.card><p class="text-sm text-ink-soft">Nenhuma carteira para mostrar. Importe a carteira para ver o resumo.</p></x-ui.card>
    @endforelse
</div>
