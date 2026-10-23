<?php

namespace App\Support;

use Transliterator;

final class Text
{
    /** Minúsculas, sem acento e sem espaços repetidos ou nas pontas: base da comparação de nomes (R7) e da busca. */
    public static function fold(string $text): string
    {
        static $transliterator = null;
        $transliterator ??= Transliterator::create('Any-Latin; Latin-ASCII; Lower()');
        $folded = $transliterator->transliterate($text);

        return trim(preg_replace('/\s+/u', ' ', $folded) ?? '');
    }
}
