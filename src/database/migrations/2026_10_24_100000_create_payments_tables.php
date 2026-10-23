<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Canal de recebimento: conta, convênio ou estabelecimento de cartão; é do credor (R45).
        Schema::create('payment_channels', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('type', 20);
            $table->string('code', 100);
            $table->string('description', 200);
            $table->boolean('active')->default(true);
            $table->timestamps();
            $table->unique(['tenant_id', 'code']);
        });

        // Pagamento: identificado por credor + canal + identificador (R48). Pendente quando o título
        // informado ainda não está na carteira (R52a); aplicado quando baixou ou gerou crédito.
        Schema::create('payments', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('channel_id')->constrained('payment_channels')->restrictOnDelete();
            $table->foreignId('import_id')->nullable()->constrained('imports')->nullOnDelete();
            $table->string('identifier', 200);
            $table->string('document', 14);
            $table->string('bill_number', 100);
            $table->foreignId('bill_id')->nullable()->constrained('bills')->restrictOnDelete();
            $table->date('paid_on');
            $table->bigInteger('amount_cents');
            $table->string('method', 20);
            $table->string('status', 20);
            $table->bigInteger('applied_cents')->default(0);
            $table->bigInteger('credit_cents')->default(0);
            $table->bigInteger('reversed_cents')->default(0);
            $table->bigInteger('credit_reversed_cents')->default(0);
            $table->timestamps();
            $table->unique(['tenant_id', 'channel_id', 'identifier']);
            $table->index('bill_id');
            $table->index(['tenant_id', 'status']);
            $table->index(['tenant_id', 'paid_on']);
        });

        // Estorno de pagamento (R60 a R64), identificado por credor + canal + identificador do estorno.
        Schema::create('payment_reversals', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('channel_id')->constrained('payment_channels')->restrictOnDelete();
            $table->foreignId('payment_id')->constrained()->restrictOnDelete();
            $table->foreignId('import_id')->nullable()->constrained('imports')->nullOnDelete();
            $table->string('identifier', 200);
            $table->date('reversed_on');
            $table->bigInteger('amount_cents');
            $table->bigInteger('from_credit_cents')->default(0);
            $table->bigInteger('from_bill_cents')->default(0);
            $table->string('reason', 300)->nullable();
            $table->timestamps();
            $table->unique(['tenant_id', 'channel_id', 'identifier']);
            $table->index('payment_id');
        });

        // Crédito do contrato (MT-22): livro de lançamentos só de inserção; o saldo é a soma. Positivo na origem
        // (excedente, título já pago, título retirado, crédito sem baixar, transferência recebida), negativo no
        // estorno e na transferência enviada.
        Schema::create('credits', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('contract_id')->constrained()->restrictOnDelete();
            $table->foreignId('payment_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->string('kind', 20);
            $table->bigInteger('amount_cents');
            $table->string('reason', 30);
            $table->string('note', 300)->nullable();
            $table->foreignId('related_contract_id')->nullable()->constrained('contracts')->restrictOnDelete();
            $table->timestamp('occurred_at')->useCurrent();
            $table->index('contract_id');
            $table->index('payment_id');
            $table->index(['tenant_id', 'occurred_at']);
        });

        // Quanto do título já foi pago (saldo = valor - pago, R54) e a política do credor para pagamentos.
        Schema::table('bills', function (Blueprint $table) {
            $table->bigInteger('paid_cents')->default(0)->after('amount_cents');
            $table->date('paid_on')->nullable()->after('paid_cents');
        });
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->string('partial_payment_policy', 20)->default('partial')->after('upcoming_display');
            $table->string('withdrawn_payment_policy', 20)->default('prevails')->after('partial_payment_policy');
            $table->string('withdrawn_reversal_policy', 20)->default('reopen')->after('withdrawn_payment_policy');
            $table->string('reversal_month_policy', 20)->default('reversal')->after('withdrawn_reversal_policy');
        });

        // Preparação da importação de pagamentos e de estornos (como import_rows, sem registro de escrita).
        DB::statement(<<<'SQL'
            create unlogged table payment_rows (
                import_id bigint not null,
                line integer not null,
                channel_code varchar(100) not null,
                identifier varchar(200) not null,
                document varchar(14),
                bill_number varchar(100),
                paid_on date,
                amount_cents bigint,
                method varchar(20),
                payment_identifier varchar(200),
                reason varchar(300),
                ok boolean not null default true
            )
        SQL);
        DB::statement('create index payment_rows_import on payment_rows (import_id, ok, paid_on, line)');
        DB::statement('create index payment_rows_import_identifier on payment_rows (import_id, channel_code, identifier)');
    }

    public function down(): void
    {
        DB::statement('drop table if exists payment_rows');
        Schema::table('tenant_settings', function (Blueprint $table) {
            $table->dropColumn(['partial_payment_policy', 'withdrawn_payment_policy', 'withdrawn_reversal_policy', 'reversal_month_policy']);
        });
        Schema::table('bills', function (Blueprint $table) {
            $table->dropColumn(['paid_cents', 'paid_on']);
        });
        Schema::dropIfExists('credits');
        Schema::dropIfExists('payment_reversals');
        Schema::dropIfExists('payments');
        Schema::dropIfExists('payment_channels');
    }
};
