<?php

namespace App\Import;

/** Linha da planilha já validada e normalizada. */
final readonly class ParsedRow
{
    public function __construct(
        public int $line,
        public string $document,
        public string $name,
        public ?string $phone,
        public ?string $email,
        public ?string $contract,
        public string $number,
        public string $dueDate,
        public int $amountCents,
        public ?string $description,
        /** Papéis declarados na coluna `papel`, separados por vírgula (holder, financial_responsible); null quando vazia (vale os dois). */
        public ?string $roles = null,
    ) {}
}
