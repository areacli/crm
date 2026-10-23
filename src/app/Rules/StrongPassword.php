<?php

namespace App\Rules;

use Closure;
use Illuminate\Contracts\Validation\ValidationRule;

/**
 * Regra de senha (R26): mínimo de 12 caracteres; recusa senha comum, só numérica ou parecida com o usuário.
 * Sem exigência de maiúscula, número ou símbolo, nem troca periódica.
 */
final class StrongPassword implements ValidationRule
{
    public const int MIN_LENGTH = 12;

    /** Senhas comuns de 12 caracteres ou mais, que passariam pelo tamanho mínimo. */
    private const array COMMON = [
        'password1234', 'password12345', 'password123456', 'qwertyuiop12', 'qwerty123456', 'qwertyuiopas', 'abcdefghijkl',
        'abcd12345678', 'abc123456789', 'senha1234567', 'senha12345678', 'mudar1234567', 'mudar@123456', 'brasil123456',
        'iloveyou1234', 'letmein12345', 'welcome12345', 'administrator', 'admin1234567', 'admin@123456', 'changeme1234',
        '123456789abc', '1q2w3e4r5t6y', '1qaz2wsx3edc', 'asdfghjkl123', 'zxcvbnm12345',
    ];

    public function __construct(private readonly ?string $identity = null) {}

    public function validate(string $attribute, mixed $value, Closure $fail): void
    {
        $password = (string) $value;

        if (mb_strlen($password) < self::MIN_LENGTH) {
            $fail('A senha precisa ter no mínimo '.self::MIN_LENGTH.' caracteres.');

            return;
        }
        if (ctype_digit($password)) {
            $fail('A senha não pode ter só números.');

            return;
        }
        if (in_array(mb_strtolower($password), self::COMMON, true)) {
            $fail('Senha muito comum.');

            return;
        }
        if ($this->identity !== null && $this->similarToIdentity($password)) {
            $fail('A senha é parecida com o usuário.');
        }
    }

    private function similarToIdentity(string $password): bool
    {
        $local = mb_strtolower(explode('@', $this->identity)[0]);
        $normalized = mb_strtolower($password);
        // Um começo de e-mail muito curto ("v5", "ana") aparece em muitas senhas sem ter relação com o usuário:
        // só vale comparar a partir de 4 caracteres.
        if (mb_strlen($local) < 4) {
            return false;
        }

        // Contém o usuário, ou é quase igual a ele (um ou dois caracteres de diferença).
        return str_contains($normalized, $local) || levenshtein($normalized, $local) <= 2;
    }
}
