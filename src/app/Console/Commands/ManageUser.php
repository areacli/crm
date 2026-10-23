<?php

namespace App\Console\Commands;

use App\Access\TemporaryPassword;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\Tenant;
use App\Models\User;
use App\Rules\StrongPassword;
use App\Support\AccessLog;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Validator;

/**
 * Comando do administrador (R25): cria, desativa, reativa e redefine a senha de usuários, fora da interface.
 * Não há cadastro aberto nem recuperação de senha por e-mail.
 */
#[Signature('crm:user {action : create, link, rename, list, deactivate, reactivate ou reset-password} {email?} {--name=} {--tenant= : nome do credor} {--profile=Gestor : perfil no credor} {--password= : senha definitiva (se omitida, é gerada uma senha temporária de 72 horas)}')]
#[Description('Administra usuários: criar, desativar, reativar e redefinir a senha')]
final class ManageUser extends Command
{
    public function handle(): int
    {
        $email = mb_strtolower(trim((string) $this->argument('email')));
        if ($email === '' && $this->argument('action') !== 'list') {
            return $this->fail('Informe o e-mail.');
        }

        return match ($this->argument('action')) {
            'create' => $this->create($email),
            'link' => $this->link($email),
            'rename' => $this->rename($email),
            'list' => $this->list(),
            'deactivate' => $this->setActive($email, false),
            'reactivate' => $this->setActive($email, true),
            'reset-password' => $this->resetPassword($email),
            default => $this->fail('Ação desconhecida. Use create, link, rename, list, deactivate, reactivate ou reset-password.'),
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
        $temporary = $this->option('password') ? null : $password;

        $user = DB::transaction(function () use ($email, $password, $temporary, $tenant, $profile) {
            $user = User::create(['name' => $this->option('name') ?: $email, 'email' => $email, 'password' => $password]);
            $user->forceFill(['temporary_password_until' => $temporary ? TemporaryPassword::expiresAt() : null])->save();
            Membership::create(['user_id' => $user->id, 'tenant_id' => $tenant->id, 'profile_id' => $profile->id]);

            return $user;
        });
        $this->audit('admin_user_created', $user);
        $this->info("Usuário {$email} criado no credor {$tenant->name} com o perfil {$profile->name}.");
        $this->announceTemporary($temporary);

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
        $temporary = $this->option('password') ? null : $password;
        $user->forceFill([
            'password' => $password, 'failed_attempts' => 0, 'locked_until' => null,
            'temporary_password_until' => $temporary ? TemporaryPassword::expiresAt() : null,
        ])->save();
        $this->audit('admin_password_reset', $user);
        $this->info('Senha redefinida.');
        $this->announceTemporary($temporary);

        return self::SUCCESS;
    }

    private function link(string $email): int
    {
        $user = User::where('email', $email)->first();
        $tenant = Tenant::where('name', $this->option('tenant'))->first();
        $profile = $tenant ? Profile::where('tenant_id', $tenant->id)->where('name', $this->option('profile'))->first() : null;
        if ($user === null || $tenant === null || $profile === null) {
            $this->error('Informe um usuário existente e, em --tenant e --profile, um credor e um perfil dele.');

            return self::FAILURE;
        }
        Membership::updateOrCreate(['user_id' => $user->id, 'tenant_id' => $tenant->id], ['profile_id' => $profile->id, 'active' => true]);
        AccessLog::record('admin_membership_linked', $user, $tenant, details: ['profile' => $profile->name]);
        $this->info("Usuário {$email} ligado ao credor {$tenant->name} com o perfil {$profile->name}.");

        return self::SUCCESS;
    }

    private function rename(string $email): int
    {
        $user = User::where('email', $email)->first();
        if ($user === null || blank($this->option('name'))) {
            $this->error('Informe um usuário existente e o novo nome em --name.');

            return self::FAILURE;
        }
        $before = $user->name;
        $user->update(['name' => $this->option('name')]);
        AccessLog::record('admin_user_renamed', $user, details: ['before' => $before, 'after' => $user->name]);
        $this->info('Nome alterado.');

        return self::SUCCESS;
    }

    private function list(): int
    {
        $rows = Membership::with(['user', 'tenant', 'profile'])->get()->map(fn (Membership $m) => [
            $m->user->email, $m->user->name, $m->tenant->name, $m->profile->name, $m->user->active && $m->active ? 'ativo' : 'inativo',
        ])->all();
        $this->table(['E-mail', 'Nome', 'Credor', 'Perfil', 'Situação'], $rows);

        return self::SUCCESS;
    }

    private function announceTemporary(?string $temporary): void
    {
        if ($temporary !== null) {
            $this->warn("Senha temporária (válida por 72 horas; não será mostrada de novo): {$temporary}");
        }
    }

    private function readPassword(string $email): ?string
    {
        if (! $this->option('password')) {
            return TemporaryPassword::generate();
        }
        $password = $this->option('password');
        $validator = Validator::make(['password' => $password], ['password' => [new StrongPassword($email)]]);
        if ($validator->fails()) {
            $this->error($validator->errors()->first('password'));

            return null;
        }

        return $password;
    }

    private function audit(string $event, User $user): void
    {
        AccessLog::record($event, $user);
    }
}
