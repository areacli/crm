<?php

namespace App\Providers\Filament;

use App\Demo\DemoMode;
use App\Filament\Pages\ChangePassword;
use App\Filament\Pages\Summary;
use App\Http\Middleware\EnforceSessionLimits;
use App\Http\Middleware\RequirePasswordChange;
use Filament\Actions\Action;
use Filament\Http\Middleware\Authenticate;
use Filament\Http\Middleware\AuthenticateSession;
use Filament\Http\Middleware\DisableBladeIconComponents;
use Filament\Http\Middleware\DispatchServingFilamentEvent;
use Filament\Pages\Enums\SubNavigationPosition;
use Filament\Panel;
use Filament\PanelProvider;
use Filament\Support\Colors\Color;
use Filament\Support\Icons\Heroicon;
use Filament\View\PanelsRenderHook;
use Illuminate\Cookie\Middleware\AddQueuedCookiesToResponse;
use Illuminate\Cookie\Middleware\EncryptCookies;
use Illuminate\Foundation\Http\Middleware\PreventRequestForgery;
use Illuminate\Routing\Middleware\SubstituteBindings;
use Illuminate\Session\Middleware\StartSession;
use Illuminate\View\Middleware\ShareErrorsFromSession;

class AdminPanelProvider extends PanelProvider
{
    public function panel(Panel $panel): Panel
    {
        return $panel
            ->default()
            ->id('crm')
            ->path('')
            ->brandName('CRM')
            ->login()
            ->databaseNotifications()
            // Faixa fixa da demonstração pública: dados fictícios e o horário da recriação.
            ->renderHook(PanelsRenderHook::BODY_START, fn () => DemoMode::enabled() ? view('filament.demo-banner', ['at' => config('crm.demo.reset_at')]) : '')
            ->userMenuItems([
                Action::make('change-password')->label('Trocar a senha')->icon(Heroicon::OutlinedKey)->url(fn () => ChangePassword::getUrl())->visible(fn () => ChangePassword::canAccess()),
            ])
            // Tema compilado com Vite e Tailwind: as classes das views próprias do CRM (resources/views/filament) entram no CSS.
            ->viteTheme('resources/css/filament/crm/theme.css')
            ->colors([
                'primary' => Color::Amber,
            ])
            ->subNavigationPosition(SubNavigationPosition::Top)
            ->discoverClusters(in: app_path('Filament/Clusters'), for: 'App\\Filament\\Clusters')
            ->discoverResources(in: app_path('Filament/Resources'), for: 'App\Filament\Resources')
            ->discoverPages(in: app_path('Filament/Pages'), for: 'App\Filament\Pages')
            ->pages([
                Summary::class,
            ])
            ->discoverWidgets(in: app_path('Filament/Widgets'), for: 'App\Filament\Widgets')
            ->middleware([
                EncryptCookies::class,
                AddQueuedCookiesToResponse::class,
                StartSession::class,
                EnforceSessionLimits::class,
                RequirePasswordChange::class,
                AuthenticateSession::class,
                ShareErrorsFromSession::class,
                PreventRequestForgery::class,
                SubstituteBindings::class,
                DisableBladeIconComponents::class,
                DispatchServingFilamentEvent::class,
            ])
            ->authMiddleware([
                Authenticate::class,
            ]);
    }
}
