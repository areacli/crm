<?php

// Mensagens de validação em português para as regras que as telas do CRM usam; o nome do campo vem de :attribute.
return [
    'required' => 'O campo :attribute é obrigatório.',
    'email' => 'O campo :attribute precisa ser um e-mail válido.',
    'max' => [
        'string' => 'O campo :attribute não pode ter mais de :max caracteres.',
        'file' => 'O campo :attribute não pode ser maior que :max kilobytes.',
        'numeric' => 'O campo :attribute não pode ser maior que :max.',
        'array' => 'O campo :attribute não pode ter mais de :max itens.',
    ],
    'min' => [
        'string' => 'O campo :attribute precisa ter pelo menos :min caracteres.',
        'numeric' => 'O campo :attribute precisa ser pelo menos :min.',
        'array' => 'Escolha pelo menos :min opção em :attribute.',
    ],
    'same' => 'O campo :attribute precisa ser igual a :other.',
    'date' => 'O campo :attribute precisa ser uma data válida.',
    'in' => 'O valor escolhido em :attribute é inválido.',
    'enum' => 'O valor escolhido em :attribute é inválido.',
    'unique' => 'Já existe um registro com esse valor em :attribute neste credor.',
    'file' => 'O campo :attribute precisa ser um arquivo.',
    'array' => 'O campo :attribute está em formato inválido.',
    'integer' => 'O campo :attribute precisa ser um número inteiro.',
    'uploaded' => 'O envio do arquivo falhou. Confira o tamanho (até 50 MB) e tente de novo.',
    'attributes' => [],
];
