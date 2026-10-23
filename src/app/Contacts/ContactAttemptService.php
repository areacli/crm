<?php

namespace App\Contacts;

use App\Enums\ContactChannel;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Models\Change;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Contract;
use App\Models\Customer;
use App\Models\User;
use App\Support\AccessLog;
use Illuminate\Support\Carbon;
use Illuminate\Support\Facades\DB;

/**
 * Registro e anulação de acionamentos (especificação 04, R69 a R77): todas as regras são conferidas aqui, no servidor,
 * no credor do cliente; a tela só ajuda. Nada é editado nem apagado: o errado é anulado, com motivo.
 */
final class ContactAttemptService
{
    public const int MAX_PAST_DAYS = 7;

    public const int MAX_RETURN_DAYS = 90;

    public const int MAX_TEXT = 2000;

    /** Janela do duplo envio: o mesmo registro do mesmo usuário em até 10 segundos é ignorado. */
    private const int DUPLICATE_SECONDS = 10;

    /**
     * @param  array{channel: ContactChannel|string, result_id: int|string, contract_id?: int|string|null, contact_used?: ?string, text?: ?string, contacted_at?: Carbon|string|null, return_at?: Carbon|string|null}  $data
     *
     * @throws ContactRefused
     */
    public function record(User $actor, Customer $customer, array $data): ContactAttempt
    {
        // R76 e RP1: registrar exige a permissão 7 e a 1, no credor do cliente (MT-3); a recusa fica registrada (R33).
        if (! $actor->hasPermission(Permission::RecordContactAttempts, $customer->tenant_id) || ! $actor->hasPermission(Permission::ViewPortfolio, $customer->tenant_id)) {
            AccessLog::record('permission_denied', $actor, $customer->tenant_id, $actor, ['permission' => Permission::RecordContactAttempts->value]);

            throw new ContactRefused('Você não tem permissão para esta ação.');
        }

        $channel = $data['channel'] instanceof ContactChannel ? $data['channel'] : ContactChannel::tryFrom((string) $data['channel']);
        if ($channel === null) {
            throw new ContactRefused('Escolha o canal do contato.');
        }

        $result = ContactResult::query()->where('tenant_id', $customer->tenant_id)->find($data['result_id'] ?? 0);
        if ($result === null) {
            throw new ContactRefused('Escolha o resultado do contato.');
        }
        if (! $result->active) {
            throw new ContactRefused('Resultado desativado; escolha outro.');
        }

        $contractId = null;
        if (! empty($data['contract_id'])) {
            $contract = Contract::query()->where('tenant_id', $customer->tenant_id)->find($data['contract_id']);
            if ($contract === null || ! $contract->customers()->whereKey($customer->id)->exists()) {
                throw new ContactRefused('O cliente não figura neste contrato.');
            }
            $contractId = $contract->id;
        }

        $now = now();
        $contactedAt = $this->moment($data['contacted_at'] ?? null) ?? $now;
        if ($contactedAt->gt($now->copy()->addMinute())) {
            throw new ContactRefused('A data do contato não pode ser futura.');
        }
        if ($contactedAt->lt($now->copy()->subDays(self::MAX_PAST_DAYS)->startOfMinute())) {
            throw new ContactRefused('Data do contato até '.self::MAX_PAST_DAYS.' dias atrás.');
        }

        $returnAt = $this->moment($data['return_at'] ?? null);
        match ($result->return_rule) {
            ReturnRule::NotAllowed => $returnAt === null || throw new ContactRefused('Este resultado não permite data de retorno.'),
            ReturnRule::Required => $returnAt !== null || throw new ContactRefused('Este resultado exige data de retorno.'),
            ReturnRule::Allowed => null,
        };
        if ($returnAt !== null) {
            if ($returnAt->lte($contactedAt)) {
                throw new ContactRefused('O retorno deve ser depois do contato.');
            }
            if ($returnAt->gt($contactedAt->copy()->addDays(self::MAX_RETURN_DAYS))) {
                throw new ContactRefused('Retorno até '.self::MAX_RETURN_DAYS.' dias depois do contato.');
            }
        }

        $text = $this->cleanText($data['text'] ?? null);
        if ($text !== null && mb_strlen($text) > self::MAX_TEXT) {
            throw new ContactRefused('O texto tem no máximo '.self::MAX_TEXT.' caracteres.');
        }
        $contact = $this->contact($channel, $data['contact_used'] ?? null);

        // Duplo envio (duplo clique, recarga): o idêntico do mesmo usuário nos últimos 10 segundos é ignorado.
        $duplicate = ContactAttempt::query()
            ->where('customer_id', $customer->id)->where('user_id', $actor->id)->where('channel', $channel->value)->where('result_id', $result->id)
            ->where('contacted_at', $contactedAt)->where('created_at', '>=', $now->copy()->subSeconds(self::DUPLICATE_SECONDS))
            ->where('contact_used', $contact)->where('text', $text)->first();
        if ($duplicate !== null) {
            return $duplicate;
        }

        return DB::transaction(function () use ($actor, $customer, $contractId, $result, $channel, $contact, $text, $contactedAt, $returnAt) {
            $attempt = ContactAttempt::create([
                'tenant_id' => $customer->tenant_id, 'customer_id' => $customer->id, 'contract_id' => $contractId, 'user_id' => $actor->id,
                'result_id' => $result->id, 'result_type' => $result->type, 'channel' => $channel, 'contact_used' => $contact, 'text' => $text,
                'contacted_at' => $contactedAt, 'return_at' => $returnAt,
            ]);
            $this->log($customer->tenant_id, $actor, 'contact_attempt', $attempt->id, 'created', null, $result->name);

            return $attempt;
        });
    }

    /**
     * R75: anular, com motivo, por quem registrou (permissão 7) ou por quem tem "anular acionamentos de outros" (8),
     * no credor do registro. O anulado continua no histórico e não conta nos totais; a anulação não se desfaz.
     *
     * @throws ContactRefused
     */
    public function void(User $actor, ContactAttempt $attempt, string $reason): ContactAttempt
    {
        $own = $attempt->user_id === $actor->id && $actor->hasPermission(Permission::RecordContactAttempts, $attempt->tenant_id);
        if (! $own && ! $actor->hasPermission(Permission::VoidOthersContactAttempts, $attempt->tenant_id)) {
            AccessLog::record('permission_denied', $actor, $attempt->tenant_id, $actor, ['permission' => Permission::VoidOthersContactAttempts->value]);

            throw new ContactRefused('Você não tem permissão para esta ação.');
        }
        $reason = trim((string) $this->cleanText($reason));
        if ($reason === '') {
            throw new ContactRefused('Informe o motivo da anulação.');
        }
        if (mb_strlen($reason) > 300) {
            throw new ContactRefused('O motivo tem no máximo 300 caracteres.');
        }
        if ($attempt->isVoided()) {
            throw new ContactRefused('Este acionamento já foi anulado.');
        }

        DB::transaction(function () use ($actor, $attempt, $reason) {
            $attempt->update(['voided_at' => now(), 'voided_by' => $actor->id, 'void_reason' => $reason]);
            $this->log($attempt->tenant_id, $actor, 'contact_attempt', $attempt->id, 'voided', null, $reason);
        });

        return $attempt;
    }

    /** R72: texto puro. Caracteres de controle invisíveis saem; quebras de linha e tabulação ficam. */
    public function cleanText(?string $text): ?string
    {
        if ($text === null) {
            return null;
        }
        $clean = preg_replace('/[\x00-\x08\x0B\x0C\x0E-\x1F\x7F\x{200B}-\x{200F}\x{202A}-\x{202E}\x{2060}\x{FEFF}]/u', '', str_replace("\r\n", "\n", $text)) ?? '';
        $clean = trim($clean);

        return $clean === '' ? null : $clean;
    }

    /** R71: contato usado: telefone até 60 caracteres, e-mail até 254, carta, presencial e outro até 300. */
    private function contact(ContactChannel $channel, ?string $raw): ?string
    {
        $contact = $this->cleanText($raw);
        if ($contact === null) {
            return null;
        }
        $max = match ($channel) {
            ContactChannel::Phone, ContactChannel::WhatsApp, ContactChannel::Sms => 60,
            ContactChannel::Email => 254,
            default => 300,
        };
        if (mb_strlen($contact) > $max) {
            throw new ContactRefused("O contato usado tem no máximo {$max} caracteres para este canal.");
        }

        return $contact;
    }

    private function moment(Carbon|string|null $value): ?Carbon
    {
        if ($value === null || $value === '') {
            return null;
        }

        return $value instanceof Carbon ? $value : Carbon::parse($value);
    }

    private function log(int $tenantId, User $actor, string $subject, int $id, string $event, ?string $before, ?string $after): void
    {
        Change::create([
            'tenant_id' => $tenantId, 'user_id' => $actor->id, 'subject_type' => $subject, 'subject_id' => $id,
            'event' => $event, 'field' => null, 'before' => $before, 'after' => $after, 'occurred_at' => now(),
        ]);
    }
}
