<?php

namespace App\Providers;

use App\Enums\Permission;
use App\Models\User;
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
        // Fora de produção, o Eloquent acusa lazy loading, atributo ausente e atributo descartado em silêncio.
        Model::shouldBeStrict(! $this->app->isProduction());
        DB::prohibitDestructiveCommands($this->app->isProduction());

        // Habilidades que não são de um modelo: as policies (descobertas sozinhas, app/Policies) cuidam do resto.
        Gate::define('view-summary', fn (User $user): bool => $user->hasAnyPermission(Permission::ViewPortfolio));
    }
}
