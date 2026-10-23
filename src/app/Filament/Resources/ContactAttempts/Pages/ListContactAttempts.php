<?php

namespace App\Filament\Resources\ContactAttempts\Pages;

use App\Filament\Resources\ContactAttempts\ContactAttemptResource;
use Filament\Resources\Pages\ListRecords;

final class ListContactAttempts extends ListRecords
{
    protected static string $resource = ContactAttemptResource::class;

    protected static ?string $title = 'Acionamentos';
}
