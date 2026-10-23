<?php

use Illuminate\Support\Facades\Schedule;

// Tarefas agendadas do CRM (operação, O8). O agendador roda em contêiner próprio: `php artisan schedule:work`.
Schedule::command('crm:clean-imports')->everyFiveMinutes()->withoutOverlapping();

// Demonstração pública: recria os dados fictícios todo dia, no horário de Brasília (só roda com CRM_DEMO=1).
Schedule::command('crm:demo-reset')->dailyAt((string) config('crm.demo.reset_at'))->timezone('America/Sao_Paulo')
    ->withoutOverlapping()->when(fn () => (bool) config('crm.demo.enabled'));
