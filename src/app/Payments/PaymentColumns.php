<?php

namespace App\Payments;

/** Colunas das planilhas de pagamentos e de estornos para a tela e as planilhas-modelo (como a R44). */
final class PaymentColumns
{
    /** @return list<array{name: string, required: bool, format: string, example: string}> */
    public static function for(string $kind): array
    {
        return $kind === 'reversals' ? [
            ['name' => 'canal', 'required' => true, 'format' => 'Código de um canal cadastrado', 'example' => '341-1234-56789'],
            ['name' => 'identificador_pagamento', 'required' => true, 'format' => 'Identificador do pagamento estornado, no canal', 'example' => 'E1234567820261019'],
            ['name' => 'identificador_estorno', 'required' => true, 'format' => 'Único dentro do canal', 'example' => 'D9876543'],
            ['name' => 'data_estorno', 'required' => true, 'format' => 'Data dd/mm/aaaa, não futura nem anterior ao pagamento', 'example' => '20/10/2026'],
            ['name' => 'valor', 'required' => true, 'format' => 'Reais, com vírgula nos centavos; até o que falta estornar', 'example' => '300,00'],
            ['name' => 'motivo', 'required' => false, 'format' => 'Texto, até 300 caracteres', 'example' => 'contestação de cartão'],
        ] : [
            ['name' => 'canal', 'required' => true, 'format' => 'Código de um canal cadastrado e ativo', 'example' => '341-1234-56789'],
            ['name' => 'identificador', 'required' => true, 'format' => 'Código do evento no canal, único dentro dele', 'example' => 'E1234567820261019'],
            ['name' => 'documento', 'required' => true, 'format' => 'CPF ou CNPJ de quem pagou', 'example' => '529.982.247-25'],
            ['name' => 'titulo', 'required' => true, 'format' => 'Número do título pago; sem ele a linha é recusada', 'example' => 'NF-1024/3'],
            ['name' => 'data_pagamento', 'required' => true, 'format' => 'Data dd/mm/aaaa, não futura', 'example' => '18/10/2026'],
            ['name' => 'valor', 'required' => true, 'format' => 'Reais, com vírgula nos centavos, maior que zero', 'example' => '400,00'],
            ['name' => 'meio', 'required' => true, 'format' => 'pix, boleto, cartão de crédito, cartão de débito, transferência, dinheiro ou outro', 'example' => 'pix'],
        ];
    }

    /** Planilha-modelo: cabeçalho e linhas fictícias que passam na conferência quando o canal e os títulos existem. */
    public static function templateCsv(string $kind): string
    {
        $header = implode(';', array_column(self::for($kind), 'name'));
        $rows = $kind === 'reversals'
            ? ['341-1234-56789;E1234567820261019;D9876543;20/10/2026;300,00;contestação de cartão']
            : [
                '341-1234-56789;E1234567820261019;529.982.247-25;T-1001;18/10/2026;400,00;pix',
                '341-1234-56789;E1234567820261020;390.533.447-05;T-1002;18/10/2026;980,50;boleto',
            ];

        return "\u{FEFF}".$header."\n".implode("\n", $rows)."\n";
    }
}
