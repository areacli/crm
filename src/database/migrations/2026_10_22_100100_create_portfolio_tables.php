<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Importação: carteira (incremento 1); pagamentos e estornos entram nos incrementos seguintes.
        Schema::create('imports', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('kind')->default('portfolio');
            $table->string('mode');
            $table->string('status');
            $table->string('original_name')->nullable();
            $table->string('stored_path')->nullable();
            $table->unsignedBigInteger('size_bytes')->default(0);
            $table->unsignedInteger('progress_percent')->default(0);
            $table->string('progress_label')->nullable();
            $table->jsonb('summary')->nullable();
            $table->string('failure_reason')->nullable();
            $table->timestamp('checked_at')->nullable();
            $table->timestamp('finished_at')->nullable();
            $table->timestamps();
            $table->index(['tenant_id', 'status']);
        });

        Schema::create('import_rejections', function (Blueprint $table) {
            $table->id();
            $table->foreignId('import_id')->constrained()->cascadeOnDelete();
            $table->unsignedInteger('line');
            $table->string('reason');
            $table->index('import_id');
        });

        // Cliente (antes "devedor"): único por credor, pelo documento (MT-9).
        Schema::create('customers', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('document', 14);
            $table->string('name', 300);
            $table->string('phone', 60)->nullable();
            $table->string('email', 254)->nullable();
            $table->timestamps();
            $table->unique(['tenant_id', 'document']);
        });

        // Contrato: obrigatório para todo título (MT-11). Sem código quando criado por omissão (MT-14).
        Schema::create('contracts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('code', 100)->nullable();
            $table->boolean('created_by_omission')->default(false);
            $table->timestamps();
            $table->index(['tenant_id', 'code']);
        });
        // Código único por credor quando informado.
        DB::statement('create unique index contracts_tenant_code_unique on contracts (tenant_id, code) where code is not null');

        // Clientes do contrato, com os papéis de cada um (MT-12, MT-13).
        Schema::create('contract_customer', function (Blueprint $table) {
            $table->foreignId('contract_id')->constrained()->cascadeOnDelete();
            $table->foreignId('customer_id')->constrained()->cascadeOnDelete();
            $table->jsonb('roles');
            $table->primary(['contract_id', 'customer_id']);
            $table->index('customer_id');
        });

        Schema::create('bills', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('contract_id')->constrained()->restrictOnDelete();
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->string('number', 100);
            $table->date('due_date');
            $table->bigInteger('amount_cents');
            $table->string('description', 300)->nullable();
            $table->string('status')->default('active');
            $table->foreignId('last_import_id')->nullable()->constrained('imports')->nullOnDelete();
            $table->foreignId('withdrawn_import_id')->nullable()->constrained('imports')->nullOnDelete();
            $table->timestamp('withdrawn_at')->nullable();
            $table->timestamps();
            $table->unique(['tenant_id', 'customer_id', 'number']);
            $table->index(['tenant_id', 'status', 'due_date']);
            $table->index('contract_id');
            $table->index('customer_id');
        });

        // Histórico de alterações: só inserção (R8, R13, R14, R16, R18, R29).
        Schema::create('changes', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('import_id')->nullable()->constrained()->nullOnDelete();
            $table->string('subject_type', 30);
            $table->unsignedBigInteger('subject_id');
            $table->string('event', 40);
            $table->string('field', 60)->nullable();
            $table->text('before')->nullable();
            $table->text('after')->nullable();
            $table->timestamp('occurred_at')->useCurrent();
            $table->index(['subject_type', 'subject_id']);
            $table->index('tenant_id');
        });
    }

    public function down(): void
    {
        Schema::dropIfExists('changes');
        Schema::dropIfExists('bills');
        Schema::dropIfExists('contract_customer');
        Schema::dropIfExists('contracts');
        Schema::dropIfExists('customers');
        Schema::dropIfExists('import_rejections');
        Schema::dropIfExists('imports');
    }
};
