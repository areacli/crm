<?php

namespace App\Filament\Resources\Profiles\Pages;

use App\Filament\Resources\Profiles\ProfileResource;
use Filament\Actions\CreateAction;
use Filament\Resources\Pages\ListRecords;

final class ListProfiles extends ListRecords
{
    protected static string $resource = ProfileResource::class;

    protected function getHeaderActions(): array
    {
        return [CreateAction::make()->label('Novo perfil')];
    }
}
