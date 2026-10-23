<?php

namespace App\Filament\Resources\Profiles\Schemas;

use App\Enums\Permission;
use App\Models\Tenant;
use Filament\Forms\Components\CheckboxList;
use Filament\Forms\Components\Hidden;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Schemas\Schema;
use Illuminate\Support\Facades\Auth;

final class ProfileForm
{
    public static function configure(Schema $schema): Schema
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageProfiles);

        return $schema->components([
            // O credor é campo do formulário só para quem gerencia perfis em mais de um (MT-8).
            Select::make('tenant_id')->label('Credor')
                ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                ->required()->disabled(fn (string $operation) => $operation === 'edit')->dehydrated()
                ->visible(count($ids) > 1),
            Hidden::make('tenant_id')->default($ids[0] ?? null)->visible(count($ids) <= 1),
            TextInput::make('name')->label('Nome do perfil')->required()->maxLength(60),
            CheckboxList::make('permissions')->label('Permissões')->required()
                ->options(collect(Permission::cases())->mapWithKeys(fn (Permission $p) => [$p->value => $p->number().'. '.$p->label()])->all())
                ->columns(2),
        ]);
    }
}
