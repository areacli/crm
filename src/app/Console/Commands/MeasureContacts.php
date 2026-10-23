<?php

namespace App\Console\Commands;

use App\Enums\Permission;
use App\Models\ContactAttempt;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\User;
use App\Portfolio\PortfolioSummary;
use App\Tenancy\TenantProvisioner;
use Illuminate\Console\Attributes\Description;
use Illuminate\Console\Attributes\Signature;
use Illuminate\Console\Command;
use Illuminate\Support\Facades\DB;

/**
 * V4 da especificação 04: a ficha com 1.000 acionamentos, a lista e o resumo com 1 milhão de acionamentos no credor, cada um
 * em até 2 segundos (restrição de desempenho). Cria um credor de medição e o apaga no fim; não use contra dados reais.
 */
#[Signature('crm:measure-contacts {attempts=1000000 : acionamentos do credor de medição} {--keep : não apaga o credor de medição no fim}')]
#[Description('Mede a ficha, a lista e o resumo de acionamentos com um volume grande (V4)')]
final class MeasureContacts extends Command
{
    public function handle(TenantProvisioner $provisioner): int
    {
        if (app()->isProduction()) {
            $this->error('Recusado em produção.');

            return self::FAILURE;
        }

        $attempts = (int) $this->argument('attempts');
        $tenant = $provisioner->create('Medição acionamentos '.now()->format('His'));
        $user = User::factory()->create(['email' => 'medicao-ac'.$tenant->id.'@exemplo.com.br']);
        Membership::create(['user_id' => $user->id, 'tenant_id' => $tenant->id, 'profile_id' => Profile::where('tenant_id', $tenant->id)->where('name', 'Gestor')->value('id')]);
        $t = $tenant->id;

        // 20 mil clientes e N acionamentos espalhados pelos últimos 92 dias, nos 11 resultados e em 5 operadores.
        DB::statement("insert into customers (tenant_id, document, name, created_at, updated_at) select $t, lpad(g::text, 11, '0'), 'Cliente '||g, now(), now() from generate_series(1, 20000) g");
        $firstCustomer = (int) DB::table('customers')->where('tenant_id', $t)->min('id');
        $operators = [$user->id];
        for ($i = 0; $i < 4; $i++) {
            $operators[] = User::factory()->create(['email' => "op$i-{$t}@exemplo.com.br"])->id;
        }
        $opList = implode(',', $operators);
        $results = DB::table('contact_results')->where('tenant_id', $t)->orderBy('id')->get(['id', 'type']);
        $resultCase = 'case (g % 11) '.collect($results)->values()->map(fn ($r, $i) => "when $i then {$r->id}")->implode(' ').' end';
        $typeCase = 'case (g % 11) '.collect($results)->values()->map(fn ($r, $i) => "when $i then '{$r->type}'")->implode(' ').' end';
        $this->time("gerar $attempts acionamentos", fn () => DB::statement(<<<SQL
            insert into contact_attempts (tenant_id, customer_id, user_id, result_id, result_type, channel, text, contacted_at, voided_at, created_at, updated_at)
            select $t, $firstCustomer + (g % 20000), (array[$opList])[1 + g % 5], $resultCase, $typeCase,
                   (array['phone','whatsapp','sms','email','letter'])[1 + g % 5], 'Texto de medição '||g, now() - (g % 92 || ' days')::interval - (g % 86400 || ' seconds')::interval,
                   case when g % 50 = 0 then now() else null end, now(), now()
            from generate_series(1, $attempts) g
        SQL));
        // Um cliente com 1.000 acionamentos, para a ficha.
        $heavy = (int) DB::table('customers')->where('tenant_id', $t)->orderBy('id')->value('id');
        DB::statement("update contact_attempts set customer_id = $heavy where id in (select id from contact_attempts where tenant_id = $t order by id limit 1000)");
        DB::statement('analyze contact_attempts');

        $this->time('ficha: primeira página (20) de um cliente com 1.000 acionamentos', fn () => ContactAttempt::query()->where('customer_id', $heavy)->orderByDesc('contacted_at')->limit(20)->with(['result', 'user', 'contract'])->get());
        $this->time('ficha: contagem para a paginação', fn () => ContactAttempt::query()->where('customer_id', $heavy)->count());
        $since = now()->subDays(7);
        $this->time('lista: primeira página (50), últimos 7 dias', fn () => ContactAttempt::query()->visibleTo($user->fresh(), Permission::ViewPortfolio)->whereNull('voided_at')->whereBetween('contacted_at', [$since, now()])->orderByDesc('contacted_at')->limit(50)->with(['customer', 'result', 'user'])->get());
        $this->time('lista: contagem do período de 7 dias', fn () => ContactAttempt::query()->where('tenant_id', $t)->whereNull('voided_at')->whereBetween('contacted_at', [$since, now()])->count());
        $this->time('lista: período de 92 dias, primeira página', fn () => ContactAttempt::query()->where('tenant_id', $t)->whereNull('voided_at')->whereBetween('contacted_at', [now()->subDays(92), now()])->orderByDesc('contacted_at')->limit(50)->get());
        $this->time('lista: período de 92 dias, contagem', fn () => ContactAttempt::query()->where('tenant_id', $t)->whereNull('voided_at')->whereBetween('contacted_at', [now()->subDays(92), now()])->count());
        $this->time('lista: 92 dias filtrada por operador e tipo', fn () => ContactAttempt::query()->where('tenant_id', $t)->whereNull('voided_at')->where('user_id', $operators[1])->where('result_type', 'no_contact')->whereBetween('contacted_at', [now()->subDays(92), now()])->orderByDesc('contacted_at')->limit(50)->get());
        $this->time('resumo da carteira (inclui os acionamentos de 7 e 30 dias)', fn () => (new PortfolioSummary($user->fresh()))->perTenant());

        if (! $this->option('keep')) {
            DB::table('contact_attempts')->where('tenant_id', $t)->delete();
            $user->delete();
            User::query()->whereIn('id', $operators)->delete();
            $tenant->delete();
            $this->line('credor de medição apagado');
        }

        return self::SUCCESS;
    }

    private function time(string $label, callable $work): mixed
    {
        $start = microtime(true);
        $result = $work();
        $this->line(sprintf('%-62s %8.3f s', $label, microtime(true) - $start));

        return $result;
    }
}
