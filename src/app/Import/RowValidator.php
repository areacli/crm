<?php

namespace App\Import;

use App\Support\BrDate;
use App\Support\Document;
use App\Support\Money;
use App\Support\Text;

/**
 * Valida uma linha da planilha contra as regras de identificação e validação (R1 a R6) e os limites de
 * tamanho de campo. Devolve a linha normalizada ou o motivo da recusa.
 */
final class RowValidator
{
    /** Limites de caracteres por campo (especificação 01, formato da planilha). */
    public const array LIMITS = ['nome' => 300, 'titulo' => 100, 'contrato' => 100, 'descricao' => 300, 'email' => 254, 'telefone' => 60];

    /**
     * @param  array<string, string>  $row
     * @return array{0: ?ParsedRow, 1: ?string} linha normalizada ou motivo da recusa
     */
    public function validate(int $line, array $row): array
    {
        if (($row['__extra'] ?? '') !== '') {
            return [null, __('import.reasons.extra_cells')];
        }
        if (($row['__short'] ?? '') !== '') {
            return [null, __('import.reasons.short_row')];
        }

        foreach (CsvFile::REQUIRED as $field) {
            if (($row[$field] ?? '') === '') {
                return [null, __('import.reasons.required', ['field' => __('import.fields.'.$field)])];
            }
        }

        if (($problem = Document::problem($row['documento'])) !== null) {
            return [null, $problem];
        }

        foreach (self::LIMITS as $field => $max) {
            if (mb_strlen($row[$field] ?? '') > $max) {
                return [null, __('import.reasons.too_long', ['field' => __('import.fields.'.$field), 'max' => $max])];
            }
        }

        $due = BrDate::parse($row['vencimento']);
        if ($due === null) {
            return [null, __('import.reasons.date_invalid')];
        }

        [$cents, $moneyProblem] = Money::parseCents($row['valor']);
        if ($cents === null) {
            return [null, $moneyProblem];
        }

        [$roles, $roleProblem] = $this->parseRoles($row['papel'] ?? '');
        if ($roleProblem !== null) {
            return [null, $roleProblem];
        }

        return [new ParsedRow(
            line: $line,
            document: Document::normalize($row['documento']),
            name: $row['nome'],
            phone: ($row['telefone'] ?? '') !== '' ? $row['telefone'] : null,
            email: ($row['email'] ?? '') !== '' ? $row['email'] : null,
            contract: ($row['contrato'] ?? '') !== '' ? $row['contrato'] : null,
            number: $row['titulo'],
            dueDate: $due->toDateString(),
            amountCents: $cents,
            description: ($row['descricao'] ?? '') !== '' ? $row['descricao'] : null,
            roles: $roles,
        ), null];
    }

    /**
     * Papéis do cliente no contrato (R9b): "titular", "responsável financeiro" ou os dois separados por barra, sem
     * diferenciar maiúsculas nem acentos. Vazio não declara papel (vale os dois). Valor desconhecido recusa a linha.
     *
     * @return array{0: ?string, 1: ?string} papéis (separados por vírgula) ou null, e o motivo da recusa
     */
    private function parseRoles(string $raw): array
    {
        if (trim($raw) === '') {
            return [null, null];
        }

        $roles = [];
        foreach (explode('/', $raw) as $token) {
            $key = str_replace(' ', '', Text::fold($token));
            $role = match ($key) {
                'titular' => 'holder',
                'responsavelfinanceiro', 'responsavel' => 'financial_responsible',
                default => null,
            };
            if ($role === null) {
                return [null, __('import.reasons.invalid_role', ['role' => trim($token)])];
            }
            $roles[$role] = $role;
        }
        sort($roles);

        return [implode(',', $roles), null];
    }
}
