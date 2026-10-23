@php
    use App\Enums\BillStatus;
    use App\Enums\UpcomingDisplay;
    use App\Models\Bill;
    use App\Portfolio\AgingBrackets;
    use App\Support\Money;

    /** @var \App\Models\Customer $customer */
    $customer = $getRecord();
    $today = now()->startOfDay();
    $settings = $customer->tenant->settings;
    $brackets = AgingBrackets::fromStored($settings->aging_brackets);

    $bills = Bill::query()->where('customer_id', $customer->id)->with('contract')->orderBy('due_date')->get();
    $active = $bills->where('status', BillStatus::Active);
    $withdrawn = $bills->where('status', BillStatus::Withdrawn);

    $overdue = $active->filter(fn ($b) => $b->due_date->lt($today));
    $upcoming = $active->filter(fn ($b) => ! $b->due_date->lt($today));
    $maxDays = $overdue->isEmpty() ? null : $overdue->max(fn ($b) => $b->daysOverdue($today));
    $display = $settings->upcoming_display;
    $byContract = $active->groupBy('contract_id');
    $roleLabels = ['holder' => 'titular', 'financial_responsible' => 'responsável financeiro'];
@endphp

<div class="space-y-6">
    <x-filament::section heading="Situação" :compact="true">
        <dl class="grid grid-cols-2 gap-4 md:grid-cols-4">
            <div>
                <dt class="text-sm text-gray-500">Vencido</dt>
                <dd class="text-lg font-semibold">R$ {{ Money::format((int) $overdue->sum('amount_cents')) }}</dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">A vencer</dt>
                <dd class="text-lg font-semibold">
                    @if ($display === UpcomingDisplay::DetailOnly)
                        —
                    @else
                        R$ {{ Money::format((int) $upcoming->sum('amount_cents')) }}
                    @endif
                </dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">Maior atraso</dt>
                <dd class="text-lg font-semibold">{{ $maxDays === null ? 'sem atraso' : $maxDays.' dias' }}</dd>
            </div>
            <div>
                <dt class="text-sm text-gray-500">Faixa</dt>
                <dd class="text-lg font-semibold">
                    {{ $maxDays === null ? 'sem atraso' : $brackets->label($brackets->indexFor($maxDays)) }}
                </dd>
            </div>
        </dl>
    </x-filament::section>

    @forelse ($byContract as $contractId => $items)
        @php($contract = $items->first()->contract->load('customers'))
        @php($responsibles = $contract->financialResponsibles())
        <x-filament::section :heading="$contract->code ? 'Contrato '.$contract->code : 'Sem contrato informado'" :compact="true">
            <div class="mb-3 text-sm">
                <span class="text-gray-500">Clientes do contrato:</span>
                @foreach ($contract->customers as $member)
                    @php($memberRoles = \App\Models\Contract::rolesOf($member))
                    <span class="me-3 inline-block">
                        <span class="font-medium">{{ $member->name }}</span>
                        <span class="text-gray-500">({{ collect($memberRoles)->map(fn ($r) => $roleLabels[$r] ?? $r)->implode(', ') ?: 'sem papel' }})</span>
                    </span>
                @endforeach
                @if ($responsibles->isNotEmpty() && ! $contract->customers->contains(fn ($m) => in_array('financial_responsible', \App\Models\Contract::rolesOf($m), true)))
                    <p class="mt-1 text-gray-500">Sem responsável financeiro declarado: os titulares respondem financeiramente.</p>
                @endif
            </div>
            <div class="overflow-x-auto">
                <table class="w-full text-sm">
                    <thead>
                        <tr class="text-left text-gray-500">
                            <th class="py-1 pe-4">Título</th>
                            <th class="py-1 pe-4">Descrição</th>
                            <th class="py-1 pe-4">Vencimento</th>
                            <th class="py-1 pe-4">Situação</th>
                            <th class="py-1 pe-4 text-end">Dias de atraso</th>
                            <th class="py-1 text-end">Valor</th>
                        </tr>
                    </thead>
                    <tbody>
                        @foreach ($items as $bill)
                            @php($days = $bill->daysOverdue($today))
                            <tr class="border-t border-gray-100 dark:border-white/10">
                                <td class="py-1 pe-4">{{ $bill->number }}</td>
                                <td class="py-1 pe-4">{{ $bill->description }}</td>
                                <td class="py-1 pe-4">{{ $bill->due_date->format('d/m/Y') }}</td>
                                <td class="py-1 pe-4">{{ $days > 0 ? 'Vencido' : 'A vencer' }}</td>
                                <td class="py-1 pe-4 text-end">{{ $days > 0 ? $days : '—' }}</td>
                                <td class="py-1 text-end">R$ {{ Money::format($bill->amount_cents) }}</td>
                            </tr>
                        @endforeach
                    </tbody>
                </table>
            </div>
        </x-filament::section>
    @empty
        <x-filament::section :compact="true">
            <p class="text-sm text-gray-500">Sem títulos em cobrança.</p>
        </x-filament::section>
    @endforelse

    @if ($withdrawn->isNotEmpty())
        <x-filament::section heading="Retirados" description="O credor tirou estes títulos da carteira; o sistema não presume o motivo." :compact="true">
            <table class="w-full text-sm">
                <tbody>
                    @foreach ($withdrawn as $bill)
                        <tr class="border-t border-gray-100 dark:border-white/10">
                            <td class="py-1 pe-4">{{ $bill->number }}</td>
                            <td class="py-1 pe-4">{{ $bill->contract->code ? 'Contrato '.$bill->contract->code : 'Sem contrato informado' }}</td>
                            <td class="py-1 pe-4">Retirado em {{ $bill->withdrawn_at?->format('d/m/Y') }}</td>
                            <td class="py-1 text-end">R$ {{ Money::format($bill->amount_cents) }}</td>
                        </tr>
                    @endforeach
                </tbody>
            </table>
        </x-filament::section>
    @endif
</div>
