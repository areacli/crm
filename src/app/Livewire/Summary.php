<?php

namespace App\Livewire;

use App\Portfolio\PortfolioSummary;
use App\Support\Navigation;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Attributes\Layout;
use Livewire\Attributes\Title;
use Livewire\Component;

/** Resumo da carteira: um bloco por credor, sem somar o que depende da configuração de cada um (R23, MT-20). */
#[Layout('layouts.app')]
#[Title('Resumo da carteira')]
final class Summary extends Component
{
    /** Sem a permissão de consultar (1), a entrada leva à primeira tela permitida (T1). */
    public function mount(): void
    {
        if (! Gate::allows('view-summary')) {
            $route = Navigation::firstRoute(Auth::user());
            abort_if($route === null || $route === 'summary', 403);
            $this->redirectRoute($route, navigate: true);
        }
    }

    /** @return list<array<string, mixed>> */
    public function summaries(): array
    {
        return (new PortfolioSummary(Auth::user()))->perTenant();
    }

    public function render()
    {
        return view('livewire.summary');
    }
}
