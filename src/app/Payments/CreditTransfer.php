<?php

namespace App\Payments;

use App\Access\AccessRefused;
use App\Enums\Permission;
use App\Models\Change;
use App\Models\Contract;
use App\Models\Credit;
use App\Models\User;
use Illuminate\Support\Facades\DB;

/**
 * Transferência de crédito entre contratos do mesmo credor (03, R55a): o único caminho para o crédito mudar de contrato.
 * Quem tem a permissão 17 no credor transfere, também entre clientes diferentes, com motivo obrigatório. Um lançamento
 * negativo na origem e um positivo no destino; nada é apagado e o total do credor não muda.
 */
final class CreditTransfer
{
    public function transfer(User $actor, Contract $from, Contract $to, int $cents, string $reason): void
    {
        if (! $actor->hasPermission(Permission::AdministerAgreements, $from->tenant_id)) {
            throw new AccessRefused('Você não tem permissão para esta ação.');
        }
        if ($from->tenant_id !== $to->tenant_id) {
            throw new AccessRefused('A transferência é só entre contratos do mesmo credor.');
        }
        if ($from->id === $to->id) {
            throw new AccessRefused('Escolha um contrato de destino diferente do de origem.');
        }
        if (trim($reason) === '') {
            throw new AccessRefused('Informe o motivo da transferência.');
        }
        if ($cents <= 0) {
            throw new AccessRefused('O valor da transferência deve ser maior que zero.');
        }

        DB::transaction(function () use ($actor, $from, $to, $cents, $reason) {
            // Bloqueia o contrato de origem: duas transferências ao mesmo tempo não gastam o mesmo crédito.
            DB::select('select id from contracts where id = ? for update', [$from->id]);
            $available = (int) Credit::query()->where('contract_id', $from->id)->sum('amount_cents');
            if ($cents > $available) {
                throw new AccessRefused('O valor é maior que o crédito disponível do contrato de origem.');
            }
            $now = now();
            Credit::create(['tenant_id' => $from->tenant_id, 'contract_id' => $from->id, 'user_id' => $actor->id, 'kind' => Credit::TRANSFER_OUT, 'amount_cents' => -$cents, 'reason' => 'transfer', 'note' => $reason, 'related_contract_id' => $to->id, 'occurred_at' => $now]);
            Credit::create(['tenant_id' => $to->tenant_id, 'contract_id' => $to->id, 'user_id' => $actor->id, 'kind' => Credit::TRANSFER_IN, 'amount_cents' => $cents, 'reason' => 'transfer', 'note' => $reason, 'related_contract_id' => $from->id, 'occurred_at' => $now]);
            foreach ([[$from, -$cents], [$to, $cents]] as [$contract, $amount]) {
                Change::create(['tenant_id' => $contract->tenant_id, 'user_id' => $actor->id, 'subject_type' => 'contract', 'subject_id' => $contract->id, 'event' => 'credit_transferred', 'field' => 'credit', 'before' => null, 'after' => (string) $amount, 'occurred_at' => $now]);
            }
        });
    }
}
