<?php

namespace App\Filament\Resources\Memberships\Pages;

use App\Access\AccessManager;
use App\Access\AccessRefused;
use App\Enums\Permission;
use App\Filament\Resources\Memberships\MembershipResource;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use Filament\Actions\Action;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ListRecords;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;

final class ListMemberships extends ListRecords
{
    protected static string $resource = MembershipResource::class;

    protected function getHeaderActions(): array
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageUsers);

        return [
            Action::make('add')->label('Novo usuário')->icon('heroicon-o-user-plus')
                ->visible(fn () => Gate::allows('create', Membership::class))
                ->modalHeading('Novo usuário')
                ->modalDescription('Se o e-mail já pertence a alguém que atua em outro credor, essa pessoa é ligada a este credor na hora e recebe um aviso. Se não, o usuário é criado com uma senha temporária, mostrada uma única vez.')
                ->schema([
                    Select::make('tenant_id')->label('Credor')
                        ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                        ->default(count($ids) === 1 ? $ids[0] : null)->required()->live()->visible(count($ids) > 1),
                    TextInput::make('email')->label('E-mail')->email()->required()->maxLength(254),
                    TextInput::make('name')->label('Nome (para quem ainda não existe)')->maxLength(150),
                    Select::make('profile_id')->label('Perfil')->required()
                        ->options(function ($get) use ($ids) {
                            $tenantId = count($ids) === 1 ? $ids[0] : (int) $get('tenant_id');

                            return Profile::query()->where('tenant_id', $tenantId)->orderBy('name')->pluck('name', 'id')->all();
                        }),
                ])
                ->action(function (array $data) use ($ids) {
                    $actor = Auth::user();
                    $tenant = Tenant::findOrFail(count($ids) === 1 ? $ids[0] : $data['tenant_id']);
                    $profile = Profile::findOrFail($data['profile_id']);
                    $email = mb_strtolower(trim($data['email']));
                    $manager = app(AccessManager::class);

                    try {
                        $existing = User::where('email', $email)->first();
                        if ($existing !== null) {
                            $manager->linkExisting($actor, $tenant, $existing, $profile);
                            Notification::make()->title("{$existing->name} ({$existing->email}) foi ligado(a) a {$tenant->name}")
                                ->body('A pessoa recebeu um aviso no sistema.')->success()->send();

                            return;
                        }
                        if (blank($data['name'] ?? null)) {
                            Notification::make()->title('Informe o nome do novo usuário')->danger()->send();

                            return;
                        }
                        [$user, $password] = $manager->createUser($actor, $tenant, $email, $data['name'], $profile);
                        Notification::make()->title("Usuário {$user->email} criado")
                            ->body("Senha temporária (válida por 72 horas; não será mostrada de novo): {$password}")
                            ->success()->persistent()->send();
                    } catch (AccessRefused $e) {
                        Notification::make()->title($e->getMessage())->danger()->send();
                    }
                }),
        ];
    }
}
