<?php

namespace App\Contacts;

use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Models\Change;
use App\Models\ContactResult;
use App\Models\Tenant;
use App\Models\User;
use App\Support\AccessLog;
use App\Support\Text;
use Illuminate\Support\Facades\DB;

/**
 * Lista de resultados do credor (R66, R67): cria, renomeia, muda a regra de retorno, ordena e desativa, com a
 * permissão 9 no credor do resultado. O tipo não muda depois de criado; resultado usado não é apagado.
 */
final class ContactResultManager
{
    public function create(User $actor, Tenant $tenant, string $name, ContactResultType $type, ReturnRule $rule): ContactResult
    {
        $this->authorize($actor, $tenant->id);
        $name = $this->validName($tenant->id, $name);

        return DB::transaction(function () use ($actor, $tenant, $name, $type, $rule) {
            // Resultado novo entra no fim da lista (revisão 2).
            $position = (int) ContactResult::query()->where('tenant_id', $tenant->id)->max('position') + 1;
            $result = ContactResult::create(['tenant_id' => $tenant->id, 'name' => $name, 'type' => $type, 'return_rule' => $rule, 'position' => $position]);
            $this->log($actor, $result, 'created', null, $name);

            return $result;
        });
    }

    public function update(User $actor, ContactResult $result, string $name, ReturnRule $rule): void
    {
        $this->authorize($actor, $result->tenant_id);
        $name = $this->validName($result->tenant_id, $name, $result->id);

        DB::transaction(function () use ($actor, $result, $name, $rule) {
            if ($result->name !== $name) {
                $this->log($actor, $result, 'renamed', $result->name, $name);
            }
            if ($result->return_rule !== $rule) {
                $this->log($actor, $result, 'return_rule_changed', $result->return_rule->value, $rule->value);
            }
            $result->update(['name' => $name, 'return_rule' => $rule]);
        });
    }

    public function setActive(User $actor, ContactResult $result, bool $active): void
    {
        $this->authorize($actor, $result->tenant_id);
        if ($result->active === $active) {
            return;
        }
        DB::transaction(function () use ($actor, $result, $active) {
            $result->update(['active' => $active]);
            $this->log($actor, $result, $active ? 'reactivated' : 'deactivated', null, $result->name);
        });
    }

    /** Move um resultado uma posição para cima ou para baixo, sem arrastar (revisão 2). */
    public function move(User $actor, ContactResult $result, int $direction): void
    {
        $this->authorize($actor, $result->tenant_id);
        DB::transaction(function () use ($actor, $result, $direction) {
            $neighbor = ContactResult::query()->where('tenant_id', $result->tenant_id)
                ->where('position', $direction < 0 ? '<' : '>', $result->position)
                ->orderBy('position', $direction < 0 ? 'desc' : 'asc')->first();
            if ($neighbor === null) {
                return;
            }
            [$a, $b] = [$result->position, $neighbor->position];
            $result->update(['position' => $b]);
            $neighbor->update(['position' => $a]);
            $this->log($actor, $result, 'moved', (string) $a, (string) $b);
        });
    }

    private function validName(int $tenantId, string $name, ?int $ignoreId = null): string
    {
        $name = trim($name);
        if ($name === '' || mb_strlen($name) > 100) {
            throw new ContactRefused('O nome do resultado precisa ter de 1 a 100 caracteres.');
        }
        $key = Text::fold($name);
        $exists = ContactResult::query()->where('tenant_id', $tenantId)->when($ignoreId, fn ($q) => $q->where('id', '!=', $ignoreId))->pluck('name')
            ->contains(fn (string $other) => Text::fold($other) === $key);
        if ($exists) {
            throw new ContactRefused('Já existe um resultado com esse nome neste credor.');
        }

        return $name;
    }

    private function authorize(User $actor, int $tenantId): void
    {
        if (! $actor->hasPermission(Permission::ManageContactResults, $tenantId)) {
            AccessLog::record('permission_denied', $actor, $tenantId, $actor, ['permission' => Permission::ManageContactResults->value]);

            throw new ContactRefused('Você não tem permissão para esta ação.');
        }
    }

    private function log(User $actor, ContactResult $result, string $event, ?string $before, ?string $after): void
    {
        Change::create([
            'tenant_id' => $result->tenant_id, 'user_id' => $actor->id, 'subject_type' => 'contact_result', 'subject_id' => $result->id,
            'event' => $event, 'field' => null, 'before' => $before, 'after' => $after, 'occurred_at' => now(),
        ]);
    }
}
