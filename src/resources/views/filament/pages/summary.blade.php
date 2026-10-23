@php
    use App\Enums\UpcomingDisplay;
    use App\Support\Money;
    $summaries = $this->summaries();
@endphp

<x-filament-panels::page>
    @forelse ($summaries as $s)
        <x-filament::section :heading="count($summaries) > 1 ? $s['tenant']->name : null" :compact="true">
            <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
                <div>
                    <dt class="text-sm text-gray-500">Clientes em cobrança</dt>
                    <dd class="text-2xl font-semibold">{{ number_format($s['upcoming_display'] === UpcomingDisplay::DetailOnly ? $s['customers_overdue'] : $s['customers'], 0, ',', '.') }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-gray-500">Títulos</dt>
                    <dd class="text-2xl font-semibold">{{ number_format($s['bills'], 0, ',', '.') }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-gray-500">Vencido</dt>
                    <dd class="text-2xl font-semibold">R$ {{ Money::format($s['overdue_cents']) }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-gray-500">A vencer</dt>
                    <dd class="text-2xl font-semibold">
                        @if ($s['upcoming_display'] === UpcomingDisplay::DetailOnly) — @else R$ {{ Money::format($s['upcoming_cents']) }} @endif
                    </dd>
                </div>
            </dl>
            @if ($s['upcoming_display'] === UpcomingDisplay::Summed)
                <p class="mt-3 text-sm text-gray-600">Em cobrança, somando o a vencer: R$ {{ Money::format($s['overdue_cents'] + $s['upcoming_cents']) }} (vencido R$ {{ Money::format($s['overdue_cents']) }}).</p>
            @endif
        </x-filament::section>

        <x-filament::section heading="Recebimentos" :compact="true">
            <dl class="grid grid-cols-1 gap-4 md:grid-cols-4">
                @foreach ($s['recovered'] as $month)
                    <div>
                        <dt class="text-sm text-gray-500">Recuperado em {{ $month['label'] }}</dt>
                        <dd class="text-2xl font-semibold">R$ {{ Money::format($month['total']) }}</dd>
                        @if ($month['methods'] !== [])
                            <dd class="text-sm text-gray-500">
                                @foreach ($month['methods'] as $method => $cents){{ $method }} R$ {{ Money::format($cents) }}@if (! $loop->last); @endif @endforeach
                            </dd>
                        @endif
                    </div>
                @endforeach
                <div>
                    <dt class="text-sm text-gray-500">Créditos dos contratos</dt>
                    <dd class="text-2xl font-semibold">R$ {{ Money::format($s['credit_cents']) }}</dd>
                </div>
                <div>
                    <dt class="text-sm text-gray-500">Pagamentos pendentes</dt>
                    <dd class="text-2xl font-semibold">{{ number_format($s['pending_count'], 0, ',', '.') }}</dd>
                    <dd class="text-sm text-gray-500">R$ {{ Money::format($s['pending_cents']) }}</dd>
                </div>
            </dl>
        </x-filament::section>

        <x-filament::section heading="Acionamentos" :compact="true">
            <div class="grid gap-6 md:grid-cols-2">
                @foreach ($s['contacts'] as $days => $block)
                    <div>
                        <p class="text-sm text-gray-500">Últimos {{ $days }} dias</p>
                        <table class="mt-1 w-full text-sm">
                            <thead><tr class="text-left text-gray-500"><th class="py-1 pe-4"></th><th class="py-1 pe-4 text-end">Acionamentos</th><th class="py-1 text-end">Clientes</th></tr></thead>
                            <tbody>
                                <tr class="border-t border-gray-100 font-semibold dark:border-white/10"><td class="py-1 pe-4">Total</td><td class="py-1 pe-4 text-end">{{ number_format($block['total']['attempts'], 0, ',', '.') }}</td><td class="py-1 text-end">{{ number_format($block['total']['customers'], 0, ',', '.') }}</td></tr>
                                @foreach ($block['types'] as $type => $numbers)
                                    <tr class="border-t border-gray-100 dark:border-white/10"><td class="py-1 pe-4">{{ \App\Enums\ContactResultType::from($type)->getLabel() }}</td><td class="py-1 pe-4 text-end">{{ number_format($numbers['attempts'], 0, ',', '.') }}</td><td class="py-1 text-end">{{ number_format($numbers['customers'], 0, ',', '.') }}</td></tr>
                                @endforeach
                            </tbody>
                        </table>
                    </div>
                @endforeach
            </div>
        </x-filament::section>

        <div class="grid gap-6 md:grid-cols-2">
            @foreach ([['title' => 'Por cliente', 'help' => 'Cada cliente na faixa do título mais atrasado, com todo o seu vencido.', 'rows' => $s['by_customer'], 'unit' => 'Clientes'],
                       ['title' => 'Por título', 'help' => 'Cada título vencido na faixa do próprio atraso.', 'rows' => $s['by_bill'], 'unit' => 'Títulos']] as $table)
                @php($max = max(1, collect($table['rows'])->max('cents')))
                <x-filament::section :heading="'Faixas de atraso — '.$table['title']" :description="$table['help']" :compact="true">
                    <table class="w-full text-sm">
                        <thead>
                            <tr class="text-left text-gray-500">
                                <th class="py-1 pe-4">Faixa (dias)</th>
                                <th class="py-1 pe-4 text-end">{{ $table['unit'] }}</th>
                                <th class="py-1 text-end">Valor vencido</th>
                                <th class="py-1 ps-4 w-1/3"></th>
                            </tr>
                        </thead>
                        <tbody>
                            @foreach ($table['rows'] as $row)
                                <tr class="border-t border-gray-100 dark:border-white/10">
                                    <td class="py-1 pe-4">{{ $row['label'] }}</td>
                                    <td class="py-1 pe-4 text-end">{{ number_format($row['count'], 0, ',', '.') }}</td>
                                    <td class="py-1 text-end">R$ {{ Money::format($row['cents']) }}</td>
                                    <td class="py-1 ps-4"><div class="h-2 rounded bg-primary-500" style="width: {{ round(100 * $row['cents'] / $max) }}%"></div></td>
                                </tr>
                            @endforeach
                        </tbody>
                    </table>
                </x-filament::section>
            @endforeach
        </div>
    @empty
        <x-filament::section :compact="true"><p class="text-sm text-gray-500">Nenhuma carteira para mostrar. Importe a carteira para ver o resumo.</p></x-filament::section>
    @endforelse
</x-filament-panels::page>
