<?php

namespace App\Console\Commands;

use App\Tenancy\TenantProvisioner;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;

#[Signature('crm:tenant {name : nome do credor}')]
#[Description('Cria um credor com a configuração inicial e os perfis Gestor e Operador')]
final class CreateTenant extends Command
{
    public function handle(TenantProvisioner $provisioner): int
    {
        $tenant = $provisioner->create((string) $this->argument('name'));
        $this->info("Credor {$tenant->name} criado (nº {$tenant->id}) com os perfis Gestor e Operador.");

        return self::SUCCESS;
    }
}
