<?php

namespace App\Filament\Resources\Profiles;

use App\Enums\Permission;
use App\Filament\Resources\Profiles\Pages\CreateProfile;
use App\Filament\Resources\Profiles\Pages\EditProfile;
use App\Filament\Resources\Profiles\Pages\ListProfiles;
use App\Filament\Resources\Profiles\Schemas\ProfileForm;
use App\Filament\Resources\Profiles\Tables\ProfilesTable;
use App\Models\Profile;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/** Perfis do credor: conjuntos de permissões (especificação 02, R30 a R35). */
class ProfileResource extends Resource
{
    protected static ?string $model = Profile::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedShieldCheck;

    protected static ?string $modelLabel = 'perfil';

    protected static ?string $pluralModelLabel = 'perfis';

    protected static ?string $slug = 'perfis';

    protected static ?int $navigationSort = 91;

    public static function getEloquentQuery(): Builder
    {
        return Profile::query()->visibleTo(Auth::user(), Permission::ManageProfiles);
    }

    public static function form(Schema $schema): Schema
    {
        return ProfileForm::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return ProfilesTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListProfiles::route('/'),
            'create' => CreateProfile::route('/novo'),
            'edit' => EditProfile::route('/{record}/editar'),
        ];
    }
}
