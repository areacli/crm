<?php

namespace App\Demo;

use App\Models\Bill;
use App\Models\Payment;
use App\Models\Tenant;
use App\Support\FakeData;
use Illuminate\Support\Facades\Artisan;

/**
 * Arquivos fictícios que a demonstração usa no lugar do que o visitante envia (o arquivo dele é descartado sem ser lido,
 * LGPD): uma carteira que traz clientes e títulos novos junto de alguns que já existem, pagamentos e estornos montados
 * a partir da carteira do dia. Cada método devolve o caminho de um CSV temporário.
 */
final class DemoFiles
{
    public const string NAME = 'arquivo-de-demonstracao.csv';

    public static function portfolio(): string
    {
        $path = tempnam(sys_get_temp_dir(), 'demo-carteira');
        $existing = (int) config('crm.demo.customers');
        // 100 clientes que já estão na carteira e 100 novos, 2 títulos cada.
        Artisan::call('crm:fake-csv', ['lines' => 400, 'path' => $path, '--per-customer' => 2, '--offset' => max(0, $existing - 100)]);

        return $path;
    }

    /** Pagamentos dos títulos em cobrança do dia: quitam, pagam metade, pagam a mais, e uma linha de título que não existe. */
    public static function payments(Tenant $tenant, string $channelCode): string
    {
        $path = tempnam(sys_get_temp_dir(), 'demo-pagamentos');
        $rows = ['canal;identificador;documento;titulo;data_pagamento;valor;meio'];
        $bills = Bill::query()->where('tenant_id', $tenant->id)->where('status', 'active')->with('customer')->orderByDesc('id')->limit(30)->get();
        $stamp = now()->format('YmdHis');
        foreach ($bills as $i => $bill) {
            $value = match ($i % 3) {
                0 => $bill->balanceCents(),
                1 => intdiv($bill->balanceCents(), 2),
                default => $bill->balanceCents() + 1500,
            };
            $rows[] = implode(';', [$channelCode, 'V'.$stamp.$i, $bill->customer->document, $bill->number, now()->format('d/m/Y'), number_format($value / 100, 2, ',', '.'), 'pix']);
        }
        $rows[] = implode(';', [$channelCode, 'V'.$stamp.'X', FakeData::cpf(3), 'NF-9999/1', now()->format('d/m/Y'), '200,00', 'pix']);
        file_put_contents($path, implode("\n", $rows)."\n");

        return $path;
    }

    /** Estornos parciais de pagamentos já aplicados do credor. */
    public static function reversals(Tenant $tenant): string
    {
        $path = tempnam(sys_get_temp_dir(), 'demo-estornos');
        $rows = ['canal;identificador_pagamento;identificador_estorno;data_estorno;valor;motivo'];
        $stamp = now()->format('YmdHis');
        $payments = Payment::query()->where('tenant_id', $tenant->id)->where('status', Payment::APPLIED)->whereColumn('reversed_cents', '<', 'amount_cents')
            ->with('channel')->orderByDesc('id')->limit(10)->get();
        foreach ($payments as $i => $payment) {
            $rows[] = implode(';', [$payment->channel->code, $payment->identifier, 'R'.$stamp.$i, now()->format('d/m/Y'), number_format(max(1, intdiv($payment->reversibleCents(), 3)) / 100, 2, ',', '.'), 'contestação do pagador']);
        }
        file_put_contents($path, implode("\n", $rows)."\n");

        return $path;
    }
}
