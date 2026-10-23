<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Registro de execução das tarefas agendadas: quando rodou e com que resultado (operação, O8).
        Schema::create('task_runs', function (Blueprint $table) {
            $table->id();
            $table->string('task', 60);
            $table->string('result', 20);
            $table->jsonb('details')->nullable();
            $table->timestamp('ran_at')->useCurrent();
            $table->index(['task', 'ran_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('task_runs');
    }
};
