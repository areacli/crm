<?php

namespace App\Filament\Pages;

use App\Portfolio\PortfolioSummary;
use BackedEnum;
use Filament\Pages\Dashboard;
use Filament\Support\Icons\Heroicon;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;

/** Resumo da carteira (R23): a entrada do sistema. Um cartão por credor (MT-20). */
class Summary extends Dashboard
{
    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedChartBar;

    protected static ?string $navigationLabel = 'Resumo';

    protected static ?string $title = 'Resumo da carteira';

    protected string $view = 'filament.pages.summary';

    protected static ?int $navigationSort = 10;

    /** Sem a permissão de consultar (1), a entrada leva à primeira tela permitida (matriz de permissões). */
    #[\Override]
    public static function canAccess(): bool
    {
        return Gate::allows('view-summary');
    }

    /** @return list<array<string, mixed>> */
    public function summaries(): array
    {
        return (new PortfolioSummary(Auth::user()))->perTenant();
    }
}
