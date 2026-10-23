<?php

namespace App\Filament\Resources\PaymentChannels\Pages;

use App\Filament\Resources\PaymentChannels\PaymentChannelResource;
use App\Models\Change;
use Filament\Resources\Pages\EditRecord;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

final class EditPaymentChannel extends EditRecord
{
    protected static string $resource = PaymentChannelResource::class;

    protected function handleRecordUpdate(Model $record, array $data): Model
    {
        $record->fill($data);
        foreach ($record->getDirty() as $field => $after) {
            if (in_array($field, ['updated_at'], true)) {
                continue;
            }
            Change::create([
                'tenant_id' => $record->tenant_id, 'user_id' => Auth::id(), 'subject_type' => 'channel', 'subject_id' => $record->id,
                'event' => 'updated', 'field' => $field, 'before' => (string) $record->getOriginal($field), 'after' => (string) $after, 'occurred_at' => now(),
            ]);
        }
        $record->save();

        return $record;
    }
}
