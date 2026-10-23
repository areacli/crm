<?php

namespace App\Filament\Resources\Profiles\Pages;

use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Filament\Resources\Profiles\ProfileResource;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\EditRecord;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

final class EditProfile extends EditRecord
{
    protected static string $resource = ProfileResource::class;

    protected function handleRecordUpdate(Model $record, array $data): Model
    {
        try {
            app(ProfileManager::class)->update(Auth::user(), $record, $data['name'], $data['permissions']);
        } catch (AccessRefused $e) {
            Notification::make()->title($e->getMessage())->danger()->send();
            $this->halt();
        }

        return $record->refresh();
    }
}
