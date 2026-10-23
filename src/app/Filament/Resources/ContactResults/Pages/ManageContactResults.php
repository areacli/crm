<?php

namespace App\Filament\Resources\ContactResults\Pages;

use App\Contacts\ContactRefused;
use App\Contacts\ContactResultManager;
use App\Enums\ContactResultType;
use App\Enums\ReturnRule;
use App\Filament\Resources\ContactResults\ContactResultResource;
use App\Models\ContactResult;
use App\Models\Tenant;
use Filament\Actions\CreateAction;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ManageRecords;
use Illuminate\Support\Facades\Auth;

final class ManageContactResults extends ManageRecords
{
    protected static string $resource = ContactResultResource::class;

    protected function getHeaderActions(): array
    {
        return [
            CreateAction::make()->label('Novo resultado')->createAnother(false)
                ->using(function (array $data): ContactResult {
                    try {
                        return app(ContactResultManager::class)->create(
                            Auth::user(), Tenant::findOrFail($data['tenant_id']), $data['name'],
                            $data['type'] instanceof ContactResultType ? $data['type'] : ContactResultType::from($data['type']),
                            $data['return_rule'] instanceof ReturnRule ? $data['return_rule'] : ReturnRule::from($data['return_rule']),
                        );
                    } catch (ContactRefused $e) {
                        Notification::make()->title($e->getMessage())->danger()->send();
                        $this->halt();
                    }
                }),
        ];
    }
}
