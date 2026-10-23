<?php

namespace App\Filament\Resources\Memberships;

use App\Enums\Permission;
use App\Filament\Resources\Memberships\Pages\ListMemberships;
use App\Filament\Resources\Memberships\Tables\MembershipsTable;
use App\Models\Membership;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/** Usuários dos credores em que a pessoa tem "gerenciar usuários": uma linha por vínculo (R36). */
class MembershipResource extends Resource
{
    protected static ?string $model = Membership::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUsers;

    protected static ?string $modelLabel = 'usuário';

    protected static ?string $pluralModelLabel = 'usuários';

    protected static ?string $navigationLabel = 'Usuários';

    protected static ?string $slug = 'usuarios';

    protected static ?int $navigationSort = 90;

    public static function getEloquentQuery(): Builder
    {
        return Membership::query()->with(['user', 'profile', 'tenant'])->visibleTo(Auth::user(), Permission::ManageUsers);
    }

    public static function table(Table $table): Table
    {
        return MembershipsTable::configure($table);
    }

    public static function getPages(): array
    {
        return ['index' => ListMemberships::route('/')];
    }
}
