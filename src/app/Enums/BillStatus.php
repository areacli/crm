<?php

namespace App\Enums;

enum BillStatus: string
{
    case Active = 'active';
    /** O credor tirou o título da carteira em cobrança; o motivo não é presumido (R14). */
    case Withdrawn = 'withdrawn';
    /** Quitado por pagamento (R50); sai da lista, dos totais e das faixas (R54). */
    case Paid = 'paid';
}
