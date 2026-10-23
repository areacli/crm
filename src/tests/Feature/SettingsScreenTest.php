<?php

use App\Enums\UpcomingDisplay;
use App\Livewire\Settings\Portfolio;
use App\Models\Change;
use App\Models\Profile;
use Livewire\Livewire;

beforeEach(function () {
    $this->tenant = makeTenant();
    $this->user = makeUser($this->tenant);
    $this->actingAs($this->user);
});

it('mostra as faixas e o tratamento atuais', function () {
    Livewire::test(Portfolio::class)
        ->assertSet('upcoming', 'separate')
        ->assertCount('brackets', 6)
        ->assertSee('Faixas de atraso');
});

// Critério: configurar 1–30, 31–60, 61–90, 91–120, 121–150, 151–180 e >180 -> o resumo mostra as 7 faixas e a mudança fica registrada.
it('salva as sete faixas e registra a mudança', function () {
    Livewire::test(Portfolio::class)
        ->set('brackets', [
            ['from' => 1, 'to' => 30], ['from' => 31, 'to' => 60], ['from' => 61, 'to' => 90], ['from' => 91, 'to' => 120],
            ['from' => 121, 'to' => 150], ['from' => 151, 'to' => 180], ['from' => 181, 'to' => null],
        ])
        ->set('upcoming', 'separate')
        ->call('save')
        ->assertDispatched('toast', message: 'Configuração salva');

    expect($this->tenant->settings->fresh()->aging_brackets)->toHaveCount(7)
        ->and(Change::where('event', 'brackets_changed')->count())->toBe(1);
});

// Critério: 1–30 e 25–60 -> "faixas sobrepostas: 25 a 30" e as faixas anteriores continuam valendo.
it('recusa faixas sobrepostas e mantém as anteriores', function () {
    Livewire::test(Portfolio::class)
        ->set('brackets', [['from' => 1, 'to' => 30], ['from' => 25, 'to' => null]])
        ->call('save')
        ->assertDispatched('toast', message: 'Faixas não salvas');

    expect($this->tenant->settings->fresh()->aging_brackets)->toHaveCount(6);
});

it('acrescenta e remove faixas na tela', function () {
    Livewire::test(Portfolio::class)
        ->call('addBracket')->assertCount('brackets', 7)
        ->call('removeBracket', 0)->assertCount('brackets', 6);
});

it('muda o tratamento dos títulos a vencer', function () {
    Livewire::test(Portfolio::class)
        ->set('brackets', [['from' => 1, 'to' => null]])
        ->set('upcoming', 'detail_only')
        ->call('save');

    expect($this->tenant->settings->fresh()->upcoming_display)->toBe(UpcomingDisplay::DetailOnly);
});

it('é só para quem pode alterar a configuração (permissão 4)', function () {
    $profile = Profile::factory()->create(['tenant_id' => $this->tenant->id, 'name' => 'Operador', 'permissions' => ['view_portfolio']]);
    $operator = makeUser($this->tenant, 'operador@exemplo.com.br');
    $operator->memberships()->update(['profile_id' => $profile->id]);

    $this->actingAs($operator->fresh())->get('/configuracao')->assertForbidden();
    $this->actingAs($operator->fresh())->get('/configuracao/carteira')->assertForbidden();
});
