<?php

namespace App\Console\Commands;

use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Rules\StrongPassword;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Comando do administrador (R25): cria, desativa, reativa e redefine a senha de usuários, fora da interface.
 * Não há cadastro aberto nem recuperação de senha por e-mail.
 */
#[Signature('crm:user {action : create, deactivate, reactivate ou reset-password} {email} {--name=} {--tenant= : nome do credor} {--profile=Gestor : perfil no credor} {--password= : senha (se omitida, é pedida)}')]
#[Description('Administra usuários: criar, desativar, reativar e redefinir a senha')]
final class ManageUser extends Command
{
    public function handle(): int
    {
        $email = mb_strtolower(trim((string) $this->argument('email')));

        return match ($this->argument('action')) {
            'create' => $this->create($email),
            'deactivate' => $this->setActive($email, false),
            'reactivate' => $this->setActive($email, true),
            'reset-password' => $this->resetPassword($email),
            default => $this->fail('Ação desconhecida. Use create, deactivate, reactivate ou reset-password.'),
        };
    }

    private function create(string $email): int
    {
        if (User::where('email', $email)->exists()) {
            $this->error('Já existe um usuário com esse e-mail.');

            return self::FAILURE;
        }
        $tenant = Tenant::where('name', $this->option('tenant'))->first();
        if ($tenant === null) {
            $this->error('Informe o credor existente em --tenant.');

            return self::FAILURE;
        }
        $profile = Profile::where('tenant_id', $tenant->id)->where('name', $this->option('profile'))->first();
        if ($profile === null) {
            $this->error('Perfil inexistente nesse credor.');

            return self::FAILURE;
        }
        $password = $this->readPassword($email);
        if ($password === null) {
            return self::FAILURE;
        }

        $user = DB::transaction(function () use ($email, $password, $tenant, $profile) {
            $user = User::create(['name' => $this->option('name') ?: $email, 'email' => $email, 'password' => $password]);
            Membership::create(['user_id' => $user->id, 'tenant_id' => $tenant->id, 'profile_id' => $profile->id]);

            return $user;
        });
        $this->audit('admin_user_created', $user);
        $this->info("Usuário {$email} criado no credor {$tenant->name} com o perfil {$profile->name}.");

        return self::SUCCESS;
    }

    private function setActive(string $email, bool $active): int
    {
        $user = User::where('email', $email)->first();
        if ($user === null) {
            $this->error('Usuário não encontrado.');

            return self::FAILURE;
        }
        $user->update(['active' => $active]);
        $this->audit($active ? 'admin_user_reactivated' : 'admin_user_deactivated', $user);
        $this->info($active ? 'Usuário reativado.' : 'Usuário desativado. As sessões abertas dele deixam de valer na próxima ação.');

        return self::SUCCESS;
    }

    private function resetPassword(string $email): int
    {
        $user = User::where('email', $email)->first();
        if ($user === null) {
            $this->error('Usuário não encontrado.');

            return self::FAILURE;
        }
        $password = $this->readPassword($email);
        if ($password === null) {
            return self::FAILURE;
        }
        $user->forceFill(['password' => $password, 'failed_attempts' => 0, 'locked_until' => null])->save();
        $this->audit('admin_password_reset', $user);
        $this->info('Senha redefinida.');

        return self::SUCCESS;
    }

    private function readPassword(string $email): ?string
    {
        $password = $this->option('password') ?: $this->secret('Senha');
        $validator = Validator::make(['password' => $password], ['password' => [new StrongPassword($email)]]);
        if ($validator->fails()) {
            $this->error($validator->errors()->first('password'));

            return null;
        }

        return $password;
    }

    private function audit(string $event, User $user): void
    {
        DB::table('access_events')->insert([
            'user_id' => $user->id, 'email' => $user->email, 'event' => $event, 'occurred_at' => now(),
        ]);
    }
}
