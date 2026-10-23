<?php

namespace App\Filament\Resources\Profiles\Pages;

use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Filament\Resources\Profiles\ProfileResource;
use App\Models\Tenant;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\CreateRecord;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\Auth;

final class CreateProfile extends CreateRecord
{
    protected static string $resource = ProfileResource::class;

    protected static bool $canCreateAnother = false;

    protected function handleRecordCreation(array $data): Model
    {
        try {
            return app(ProfileManager::class)->create(Auth::user(), Tenant::findOrFail($data['tenant_id']), $data['name'], $data['permissions']);
        } catch (AccessRefused $e) {
            Notification::make()->title($e->getMessage())->danger()->send();
            $this->halt();
        }
    }
}
