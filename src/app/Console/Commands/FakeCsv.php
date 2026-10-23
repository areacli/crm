<?php

namespace App\Console\Commands;

use App\Support\FakeData;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('crm:fake-csv {lines : número de linhas (títulos)} {path : arquivo de saída} {--per-customer=2 : títulos por cliente} {--offset=0 : deslocamento da numeração dos clientes}')]
#[Description('Gera uma planilha de carteira fictícia, com CPFs válidos, no formato da especificação 01')]
final class FakeCsv extends Command
{
    public function handle(): int
    {
        $lines = (int) $this->argument('lines');
        $per = max(1, (int) $this->option('per-customer'));
        $offset = (int) $this->option('offset');
        $out = fopen((string) $this->argument('path'), 'wb');
        fwrite($out, "documento;nome;telefone;email;contrato;titulo;vencimento;valor;descricao\n");

        for ($i = 0; $i < $lines; $i++) {
            $customer = $offset + intdiv($i, $per);
            $days = 1 + (($customer * 37 + $i * 11) % 500);
            $due = now()->subDays($days - 20)->format('d/m/Y');  // alguns títulos a vencer
            $cents = 5000 + (($i * 7919) % 250_000);
            fwrite($out, implode(';', [
                FakeData::cpf($customer), FakeData::name($customer), '(11) 9'.str_pad((string) ($customer % 100_000_000), 8, '0', STR_PAD_LEFT),
                'cliente'.$customer.'@exemplo.com.br', 'CT-'.str_pad((string) $customer, 7, '0', STR_PAD_LEFT),
                'NF-'.$customer.'/'.($i % $per + 1), $due, number_format($cents / 100, 2, ',', '.'), 'Mensalidade',
            ])."\n");
        }
        fclose($out);
        $this->info("{$lines} linhas gravadas em ".$this->argument('path'));

        return self::SUCCESS;
    }
}
