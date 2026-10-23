<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Credor (tenant). Toda tabela de domínio aponta para ele (MT-1).
        Schema::create('tenants', function (Blueprint $table) {
            $table->id();
            $table->string('name');
            $table->boolean('active')->default(true);
            $table->timestamps();
        });

        // Configuração do credor: faixas de atraso (R18) e tratamento do a vencer (R20).
        Schema::create('tenant_settings', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->unique()->constrained()->cascadeOnDelete();
            $table->jsonb('aging_brackets');
            $table->string('upcoming_display')->default('separate');
            $table->timestamps();
        });

        // Perfil: conjunto de permissões, por credor (MT-21).
        Schema::create('profiles', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name');
            $table->jsonb('permissions');
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
        });

        // Vínculo usuário × credor × perfil (MT-2). Um usuário pode ter vários vínculos.
        Schema::create('memberships', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->constrained()->cascadeOnDelete();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('profile_id')->constrained()->restrictOnDelete();
            $table->boolean('active')->default(true);
            $table->timestamps();
            $table->unique(['user_id', 'tenant_id']);
            $table->index('tenant_id');
        });

        Schema::table('users', function (Blueprint $table) {
            $table->boolean('active')->default(true)->after('password');
            $table->timestamp('locked_until')->nullable()->after('active');
            $table->unsignedSmallInteger('failed_attempts')->default(0)->after('locked_until');
            $table->timestamp('last_login_at')->nullable()->after('failed_attempts');
        });

        // Eventos de acesso: entradas, saídas, bloqueios e ações do administrador (R29).
        Schema::create('access_events', function (Blueprint $table) {
            $table->id();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('email')->nullable();
            $table->string('event');
            $table->string('ip', 45)->nullable();
            $table->jsonb('details')->nullable();
            $table->timestamp('occurred_at')->useCurrent();
            $table->index(['user_id', 'occurred_at']);
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('access_events');
        Schema::table('users', function (Blueprint $table) {
            $table->dropColumn(['active', 'locked_until', 'failed_attempts', 'last_login_at']);
        });
        Schema::dropIfExists('memberships');
        Schema::dropIfExists('profiles');
        Schema::dropIfExists('tenant_settings');
        Schema::dropIfExists('tenants');
    }
};
