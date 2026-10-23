<?php

namespace App\Providers;

use App\Enums\Permission;
use App\Models\User;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Model;
use Illuminate\Support\Facades\DB;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\ServiceProvider;

class AppServiceProvider extends ServiceProvider
{
    /**
     * Register any application services.
     */
    #[\Override]
    public function register(): void
    {
        //
    }

    /**
     * Bootstrap any application services.
     */
    public function boot(): void
    {
        // Padrão de interface P22: toda tabela do CRM mostra 20 registros por página, com 20, 50 ou 100 à escolha do usuário.
        Table::configureUsing(fn (Table $table) => $table->paginationPageOptions([20, 50, 100])->defaultPaginationPageOption(20));

        // Fora de produção, o Eloquent acusa lazy loading, atributo ausente e atributo descartado em silêncio.
        Model::shouldBeStrict(! $this->app->isProduction());
        DB::prohibitDestructiveCommands($this->app->isProduction());

        // Habilidades que não são de um modelo: as policies (descobertas sozinhas, app/Policies) cuidam do resto.
        Gate::define('view-summary', fn (User $user): bool => $user->hasAnyPermission(Permission::ViewPortfolio));
    }
}
