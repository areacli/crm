<?php

namespace App\Enums;

use App\Support\Contracts\HasColor;
use App\Support\Contracts\HasLabel;

/** Estados da importação, conforme a tabela de transições do domínio. */
enum ImportStatus: string implements HasColor, HasLabel
{
    case Received = 'received';
    case Checking = 'checking';
    case Checked = 'checked';
    case Confirming = 'confirming';
    case Confirmed = 'confirmed';
    case Discarded = 'discarded';
    case Rejected = 'rejected';
    case Failed = 'failed';

    /** Estados em que a importação ocupa o credor (uma por vez, R10 e caso de exceção). */
    public function isInProgress(): bool
    {
        return in_array($this, [self::Received, self::Checking, self::Checked, self::Confirming], true);
    }

    public function isFinal(): bool
    {
        return ! $this->isInProgress();
    }

    public function getLabel(): string
    {
        return match ($this) {
            self::Received => 'Recebida',
            self::Checking => 'Em conferência',
            self::Checked => 'Conferida, aguardando confirmação',
            self::Confirming => 'Em confirmação',
            self::Confirmed => 'Confirmada',
            self::Discarded => 'Descartada',
            self::Rejected => 'Arquivo recusado',
            self::Failed => 'Falhou',
        };
    }

    public function getColor(): string
    {
        return match ($this) {
            self::Confirmed => 'success',
            self::Failed, self::Rejected => 'danger',
            self::Checked => 'warning',
            default => 'gray',
        };
    }
}
