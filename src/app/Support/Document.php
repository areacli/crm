<?php

namespace App\Support;

/**
 * Documento do cliente: CPF (11 dígitos) ou CNPJ (14 caracteres, numérico ou alfanumérico).
 * O documento é identificado sem máscara (R1) e precisa ter dígitos verificadores válidos (R2).
 */
final class Document
{
    /** Remove a máscara e põe em maiúsculas: "529.982.247-25" vira "52998224725". */
    public static function normalize(string $raw): string
    {
        return strtoupper(preg_replace('/[^0-9A-Za-z]/', '', $raw) ?? '');
    }

    /** Motivo da recusa ("CPF inválido", "CNPJ inválido", "documento inválido") ou null quando válido. */
    public static function problem(string $raw): ?string
    {
        $document = self::normalize($raw);

        return match (strlen($document)) {
            11 => self::validCpf($document) ? null : 'CPF inválido',
            14 => self::validCnpj($document) ? null : 'CNPJ inválido',
            default => 'documento inválido: deve ter 11 dígitos (CPF) ou 14 caracteres (CNPJ)',
        };
    }

    public static function isCpf(string $document): bool
    {
        return strlen($document) === 11;
    }

    /** CPF/CNPJ mascarado para a lista; o documento completo só aparece na ficha. */
    public static function mask(string $document): string
    {
        if (strlen($document) === 11) {
            return substr($document, 0, 3).'.***.***-'.substr($document, 9, 2);
        }

        return substr($document, 0, 2).'.***.***/****-'.substr($document, 12, 2);
    }

    /** Documento completo com pontuação, para a ficha do cliente. */
    public static function format(string $document): string
    {
        if (strlen($document) === 11) {
            return substr($document, 0, 3).'.'.substr($document, 3, 3).'.'.substr($document, 6, 3).'-'.substr($document, 9, 2);
        }

        return substr($document, 0, 2).'.'.substr($document, 2, 3).'.'.substr($document, 5, 3).'/'.substr($document, 8, 4).'-'.substr($document, 12, 2);
    }

    private static function validCpf(string $cpf): bool
    {
        if (! ctype_digit($cpf) || preg_match('/^(\d)\1{10}$/', $cpf)) {
            return false;
        }

        for ($length = 9; $length <= 10; $length++) {
            $sum = 0;
            for ($i = 0; $i < $length; $i++) {
                $sum += (int) $cpf[$i] * ($length + 1 - $i);
            }
            $digit = ($sum * 10) % 11 % 10;
            if ($digit !== (int) $cpf[$length]) {
                return false;
            }
        }

        return true;
    }

    /**
     * CNPJ numérico ou alfanumérico (Receita Federal, desde julho de 2026): cada caractere vale
     * seu código ASCII menos 48; pesos de 2 a 9 da direita para a esquerda; módulo 11.
     * Os dois últimos caracteres são sempre dígitos.
     */
    private static function validCnpj(string $cnpj): bool
    {
        if (! preg_match('/^[0-9A-Z]{12}[0-9]{2}$/', $cnpj) || preg_match('/^(.)\1{13}$/', $cnpj)) {
            return false;
        }

        foreach ([12, 13] as $position) {
            $sum = 0;
            $weight = 2;
            for ($i = $position - 1; $i >= 0; $i--) {
                $sum += (ord($cnpj[$i]) - 48) * $weight;
                $weight = $weight === 9 ? 2 : $weight + 1;
            }
            $rest = $sum % 11;
            $digit = $rest < 2 ? 0 : 11 - $rest;
            if ($digit !== (int) $cnpj[$position]) {
                return false;
            }
        }

        return true;
    }
}
