<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Papéis declarados na coluna `papel` da planilha (R9b); nulo quando a coluna está vazia.
        DB::statement('alter table import_rows add column roles varchar(60)');
    }

    public function down(): void
    {
        DB::statement('alter table import_rows drop column roles');
    }
};
