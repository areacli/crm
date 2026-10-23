<?php

/*
| Configuração própria do CRM. O modo de demonstração (CRM_DEMO=1) vale só na instalação pública da vitrine do blog:
| usuários públicos, dados fictícios recriados todo dia, arquivo enviado trocado por um fictício e faixa de aviso.
| Fica fora das regras do produto (decisão do Paulo, 19/10/2026).
*/
return [
    'demo' => [
        'enabled' => (bool) env('CRM_DEMO', false),
        // Domínio dos e-mails dos usuários públicos: gestor@<domínio> e operador@<domínio>.
        'domain' => env('CRM_DEMO_DOMAIN', 'demo.exemplo.com.br'),
        'tenant' => env('CRM_DEMO_TENANT', 'Escola Alfa'),
        'customers' => (int) env('CRM_DEMO_CUSTOMERS', 1000),
        // Horário de Brasília da recriação diária.
        'reset_at' => env('CRM_DEMO_RESET_AT', '04:00'),
    ],
];
