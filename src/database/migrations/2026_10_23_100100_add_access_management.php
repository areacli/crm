<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Senha temporária (R37): vale até este instante; vazio depois da troca (R38).
        Schema::table('users', function (Blueprint $table) {
            $table->timestamp('temporary_password_until')->nullable()->after('last_login_at');
        });

        // O registro de acesso passa a guardar o credor do registro e quem agiu (R42, MT-3).
        Schema::table('access_events', function (Blueprint $table) {
            $table->foreignId('tenant_id')->nullable()->after('user_id')->constrained()->nullOnDelete();
            $table->foreignId('actor_id')->nullable()->after('tenant_id')->constrained('users')->nullOnDelete();
            $table->index(['tenant_id', 'occurred_at']);
        });

        // Avisos dentro do sistema (A5: quem foi ligado a um credor recebe um aviso).
        Schema::create('notifications', function (Blueprint $table) {
            $table->uuid('id')->primary();
            $table->string('type');
            $table->morphs('notifiable');
            $table->jsonb('data');
            $table->timestamp('read_at')->nullable();
            $table->timestamps();
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('notifications');
        Schema::table('access_events', function (Blueprint $table) {
            $table->dropConstrainedForeignId('actor_id');
            $table->dropConstrainedForeignId('tenant_id');
        });
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn('temporary_password_until');
        });
    }
};
