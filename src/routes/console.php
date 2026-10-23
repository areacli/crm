<?php

use Illuminate\Support\Facades\Schedule;

// Tarefas agendadas do CRM (operação, O8). O agendador roda em contêiner próprio: `php artisan schedule:work`.
Schedule::command('crm:clean-imports')->everyFiveMinutes()->withoutOverlapping();
