<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Support\Facades\DB;

return new class extends Migration
{
    public function up(): void
    {
        // Tabela de preparação da importação (decisão 0004: gravação em lote): sem registro de escrita
        // antecipada, porque só vive entre a conferência e a confirmação ou o descarte.
        DB::statement(<<<'SQL'
            create unlogged table import_rows (
                import_id bigint not null,
                line integer not null,
                document varchar(14) not null,
                number varchar(100) not null,
                name varchar(300),
                name_key varchar(300),
                phone varchar(60),
                email varchar(254),
                contract varchar(100),
                due_date date,
                amount_cents bigint,
                description varchar(300),
                ok boolean not null default true,
                keep_document boolean not null default false
            )
        SQL);
        DB::statement('create index import_rows_import_document_number on import_rows (import_id, document, number)');
    }

    public function down(): void
    {
        DB::statement('drop table if exists import_rows');
    }
};
