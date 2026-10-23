<?php

// Textos da importação de carteira que o usuário lê (motivos de recusa e mensagens da conferência).
return [
    'reasons' => [
        'extra_cells' => 'linha com mais colunas que o cabeçalho',
        'short_row' => 'linha incompleta',
        'required' => ':field obrigatório',
        'date_invalid' => 'data inválida',
        'too_long' => ':field acima de :max caracteres',
        'duplicate_bill' => 'título repetido na linha :line',
        'invalid_role' => 'papel inválido: :role',
        'divergent_names' => 'nomes diferentes para o mesmo documento: linhas :lines',
    ],
    'fields' => [
        'documento' => 'documento',
        'nome' => 'nome',
        'titulo' => 'título',
        'vencimento' => 'vencimento',
        'valor' => 'valor',
        'telefone' => 'telefone',
        'email' => 'e-mail',
        'contrato' => 'contrato',
        'descricao' => 'descrição',
        'papel' => 'papel',
    ],
];
