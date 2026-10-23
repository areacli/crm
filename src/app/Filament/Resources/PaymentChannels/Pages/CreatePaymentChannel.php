<?php

namespace App\Filament\Resources\PaymentChannels\Pages;

use App\Filament\Resources\PaymentChannels\PaymentChannelResource;
use App\Models\Change;
use Filament\Resources\Pages\CreateRecord;
use Illuminate\Support\Facades\Auth;

final class CreatePaymentChannel extends CreateRecord
{
    protected static string $resource = PaymentChannelResource::class;

    protected static bool $canCreateAnother = false;

    /** R45: tudo fica registrado (quem, quando, antes, depois). */
    protected function afterCreate(): void
    {
        $channel = $this->getRecord();
        Change::create([
            'tenant_id' => $channel->tenant_id, 'user_id' => Auth::id(), 'subject_type' => 'channel', 'subject_id' => $channel->id,
            'event' => 'created', 'field' => 'code', 'before' => null, 'after' => $channel->code, 'occurred_at' => now(),
        ]);
    }
}
