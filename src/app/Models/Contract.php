<?php

namespace App\Models;

use App\Models\Concerns\BelongsToTenant;
use Database\Factories\ContractFactory;
use Illuminate\Database\Eloquent\Attributes\Fillable;
use Illuminate\Database\Eloquent\Factories\HasFactory;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Database\Eloquent\Relations\BelongsToMany;
use Illuminate\Database\Eloquent\Relations\HasMany;
use Illuminate\Support\Collection;

/** Contrato: todo título existe dentro de um (MT-11); pertence a N clientes do mesmo credor (MT-12). */
#[Fillable(['tenant_id', 'code', 'created_by_omission'])]
class Contract extends Model
{
    /** @use HasFactory<ContractFactory> */
    use BelongsToTenant, HasFactory;

    protected function casts(): array
    {
        return ['created_by_omission' => 'boolean'];
    }

    public function customers(): BelongsToMany
    {
        return $this->belongsToMany(Customer::class)->withPivot('roles');
    }

    public function bills(): HasMany
    {
        return $this->hasMany(Bill::class);
    }

    public function credits(): HasMany
    {
        return $this->hasMany(Credit::class);
    }

    /** Crédito do contrato: a soma dos lançamentos (MT-22, R55b). */
    public function creditCents(): int
    {
        return (int) $this->credits()->sum('amount_cents');
    }

    /** @return list<string> papéis (holder, financial_responsible) do cliente neste contrato */
    public static function rolesOf(Customer $customer): array
    {
        return json_decode((string) ($customer->pivot->roles ?? '[]'), true) ?: [];
    }

    /**
     * Responsáveis financeiros: os clientes declarados com esse papel; se ninguém foi declarado, os titulares
     * (decisão do Paulo, 23/10/2026; MT-16). Derivado, não gravado: uma carga que declara um responsável muda o resultado.
     *
     * @return Collection<int, Customer>
     */
    public function financialResponsibles(): Collection
    {
        $declared = $this->customers->filter(fn (Customer $c) => in_array('financial_responsible', self::rolesOf($c), true));

        return $declared->isNotEmpty()
            ? $declared->values()
            : $this->customers->filter(fn (Customer $c) => in_array('holder', self::rolesOf($c), true))->values();
    }
}
