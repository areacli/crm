<?php

namespace App\Portfolio;

/**
 * Faixas de atraso do credor (R18): começam em 1 dia, não têm buraco nem sobreposição e a última é aberta.
 * Cada faixa é ['from' => início, 'to' => fim ou null].
 */
final class AgingBrackets
{
    /** @param list<array{from: int, to: ?int}> $brackets */
    private function __construct(public readonly array $brackets) {}

    /**
     * @param  list<array{from: mixed, to: mixed}>  $input
     *
     * @throws InvalidBrackets
     */
    public static function from(array $input): self
    {
        if ($input === []) {
            throw new InvalidBrackets('informe ao menos uma faixa');
        }

        $brackets = array_map(fn (array $b) => [
            'from' => (int) $b['from'],
            'to' => ($b['to'] ?? null) === null || $b['to'] === '' ? null : (int) $b['to'],
        ], array_values($input));
        usort($brackets, fn ($a, $b) => $a['from'] <=> $b['from']);

        if ($brackets[0]['from'] !== 1) {
            throw new InvalidBrackets('as faixas começam em 1 dia de atraso');
        }

        $count = count($brackets);
        foreach ($brackets as $i => $bracket) {
            $isLast = $i === $count - 1;

            if ($isLast && $bracket['to'] !== null) {
                throw new InvalidBrackets('a última faixa deve ser aberta (sem fim)');
            }
            if (! $isLast && $bracket['to'] === null) {
                throw new InvalidBrackets('só a última faixa pode ser aberta');
            }
            if ($bracket['to'] !== null && $bracket['to'] < $bracket['from']) {
                throw new InvalidBrackets("faixa {$bracket['from']} a {$bracket['to']} com fim antes do início");
            }
            if (! $isLast) {
                $next = $brackets[$i + 1];
                if ($next['from'] <= $bracket['to']) {
                    throw new InvalidBrackets("faixas sobrepostas: {$next['from']} a {$bracket['to']}");
                }
                if ($next['from'] > $bracket['to'] + 1) {
                    throw new InvalidBrackets('buraco entre as faixas: '.($bracket['to'] + 1).' a '.($next['from'] - 1));
                }
            }
        }

        return new self($brackets);
    }

    /** @param list<array{from: int, to: ?int}> $stored */
    public static function fromStored(array $stored): self
    {
        return self::from($stored);
    }

    /** Índice da faixa (a partir de 0) em que os dias de atraso caem; null para quem não está em atraso. */
    public function indexFor(int $daysOverdue): ?int
    {
        if ($daysOverdue < 1) {
            return null;
        }
        foreach ($this->brackets as $i => $bracket) {
            if ($daysOverdue >= $bracket['from'] && ($bracket['to'] === null || $daysOverdue <= $bracket['to'])) {
                return $i;
            }
        }

        return null;
    }

    public function label(int $index): string
    {
        $b = $this->brackets[$index];

        return $b['to'] === null ? 'mais de '.($b['from'] - 1) : "{$b['from']}–{$b['to']}";
    }

    /** @return list<string> */
    public function labels(): array
    {
        return array_map(fn (int $i) => $this->label($i), array_keys($this->brackets));
    }

    /**
     * Expressão SQL que dá o índice da faixa para uma coluna de dias de atraso.
     * Os limites são inteiros validados, nunca texto do usuário.
     */
    public function sqlIndex(string $daysColumn): string
    {
        $whens = [];
        foreach ($this->brackets as $i => $b) {
            $whens[] = $b['to'] === null
                ? sprintf('when %s >= %d then %d', $daysColumn, $b['from'], $i)
                : sprintf('when %s between %d and %d then %d', $daysColumn, $b['from'], $b['to'], $i);
        }

        return 'case '.implode(' ', $whens).' end';
    }
}
