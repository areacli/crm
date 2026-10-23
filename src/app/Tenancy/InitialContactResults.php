<?php

namespace App\Tenancy;

use App\Enums\ContactResultType;
use App\Enums\ReturnRule;
use App\Models\ContactResult;
use App\Models\Tenant;

/** Lista inicial de resultados de acionamento (R68): cada credor novo recebe uma cópia e depois a edita sozinho. */
final class InitialContactResults
{
    /** @var list<array{0: string, 1: ContactResultType, 2: ReturnRule}> */
    public const array LIST = [
        ['Pediu para retornar depois', ContactResultType::SpokeWithCustomer, ReturnRule::Required],
        ['Negociação em andamento', ContactResultType::SpokeWithCustomer, ReturnRule::Allowed],
        ['Disse que já pagou', ContactResultType::SpokeWithCustomer, ReturnRule::Allowed],
        ['Contesta a dívida', ContactResultType::SpokeWithCustomer, ReturnRule::Allowed],
        ['Recusou pagar', ContactResultType::SpokeWithCustomer, ReturnRule::Allowed],
        ['Recado com terceiro', ContactResultType::SpokeWithThirdParty, ReturnRule::Allowed],
        ['Terceiro não conhece o cliente', ContactResultType::SpokeWithThirdParty, ReturnRule::NotAllowed],
        ['Não atendeu', ContactResultType::NoContact, ReturnRule::Allowed],
        ['Caixa postal', ContactResultType::NoContact, ReturnRule::Allowed],
        ['Mensagem enviada, sem resposta', ContactResultType::NoContact, ReturnRule::Allowed],
        ['Número ou endereço inexistente', ContactResultType::NoContact, ReturnRule::NotAllowed],
    ];

    public static function createFor(Tenant $tenant): void
    {
        foreach (self::LIST as $i => [$name, $type, $rule]) {
            ContactResult::create(['tenant_id' => $tenant->id, 'name' => $name, 'type' => $type, 'return_rule' => $rule, 'position' => $i + 1]);
        }
    }
}
