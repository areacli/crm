<?php

use Illuminate\Database\Migrations\Migration;
use Illuminate\Database\Schema\Blueprint;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Schema;

return new class extends Migration
{
    public function up(): void
    {
        // Resultados de acionamento: lista do credor, mantida por quem gerencia resultados (R66, R67).
        Schema::create('contact_results', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->string('name', 100);
            $table->string('type', 30);
            $table->string('return_rule', 20);
            $table->boolean('active')->default(true);
            $table->unsignedInteger('position')->default(0);
            $table->timestamps();
            $table->unique(['tenant_id', 'name']);
            $table->index(['tenant_id', 'position']);
        });

        // Acionamento: tentativa de contato com um cliente (R69). Só inserção, mais a marca da anulação (R75).
        Schema::create('contact_attempts', function (Blueprint $table) {
            $table->id();
            $table->foreignId('tenant_id')->constrained()->cascadeOnDelete();
            $table->foreignId('customer_id')->constrained()->restrictOnDelete();
            $table->foreignId('contract_id')->nullable()->constrained()->restrictOnDelete();
            $table->foreignId('user_id')->nullable()->constrained()->nullOnDelete();
            $table->foreignId('result_id')->constrained('contact_results')->restrictOnDelete();
            // Cópia do tipo do resultado no momento do registro: o tipo nunca muda (R66), então os números do resumo
            // não precisam juntar com a tabela de resultados.
            $table->string('result_type', 30);
            $table->string('channel', 20);
            $table->string('contact_used', 300)->nullable();
            $table->text('text')->nullable();
            $table->timestamp('contacted_at');
            $table->timestamp('return_at')->nullable();
            $table->timestamp('voided_at')->nullable();
            $table->foreignId('voided_by')->nullable()->constrained('users')->nullOnDelete();
            $table->string('void_reason', 300)->nullable();
            $table->timestamps();
            // Ficha: os acionamentos de um cliente do mais recente ao mais antigo (R74).
            $table->index(['customer_id', 'contacted_at']);
            // Lista e resumo do credor por período (R78, R79); a anulação filtra na própria consulta.
            $table->index(['tenant_id', 'contacted_at']);
        });

        // Credores que já existem recebem a lista inicial de resultados (R68).
        $now = now();
        foreach (DB::table('tenants')->pluck('id') as $tenantId) {
            DB::table('contact_results')->insert(array_map(
                fn (array $r, int $i) => ['tenant_id' => $tenantId, 'name' => $r[0], 'type' => $r[1], 'return_rule' => $r[2], 'position' => $i + 1, 'created_at' => $now, 'updated_at' => $now],
                self::INITIAL,
                array_keys(self::INITIAL),
            ));
        }
    }

    /** Lista inicial de resultados (R68): nome, tipo, regra de retorno. */
    private const array INITIAL = [
        ['Pediu para retornar depois', 'spoke_with_customer', 'required'],
        ['Negociação em andamento', 'spoke_with_customer', 'allowed'],
        ['Disse que já pagou', 'spoke_with_customer', 'allowed'],
        ['Contesta a dívida', 'spoke_with_customer', 'allowed'],
        ['Recusou pagar', 'spoke_with_customer', 'allowed'],
        ['Recado com terceiro', 'spoke_with_third_party', 'allowed'],
        ['Terceiro não conhece o cliente', 'spoke_with_third_party', 'not_allowed'],
        ['Não atendeu', 'no_contact', 'allowed'],
        ['Caixa postal', 'no_contact', 'allowed'],
        ['Mensagem enviada, sem resposta', 'no_contact', 'allowed'],
        ['Número ou endereço inexistente', 'no_contact', 'not_allowed'],
    ];

    public function down(): void
    {
        Schema::dropIfExists('contact_attempts');
        Schema::dropIfExists('contact_results');
    }
};
