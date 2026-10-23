<?php

use App\Enums\UpcomingDisplay;
use App\Models\Change;
use App\Models\TenantSettings;
use App\Portfolio\AgingBrackets;
use App\Portfolio\InvalidBrackets;
use App\Portfolio\SettingsService;

// R18: o sistema começa com 1–30, 31–60, 61–90, 91–180, 181–360 e mais de 360 dias.
it('começa com as seis faixas padrão', function () {
    $brackets = AgingBrackets::from(TenantSettings::DEFAULT_BRACKETS);

    expect($brackets->labels())->toBe(['1–30', '31–60', '61–90', '91–180', '181–360', 'mais de 360']);
});

it('classifica os dias de atraso na faixa certa', function (int $days, ?int $index) {
    expect(AgingBrackets::from(TenantSettings::DEFAULT_BRACKETS)->indexFor($days))->toBe($index);
})->with([
    'a vencer' => [0, null], 'primeiro dia' => [1, 0], 'limite' => [30, 0], 'seguinte' => [31, 1],
    // R17: vencimento 10/09/2026 e hoje 18/10/2026 são 38 dias, faixa 31–60.
    'exemplo da especificação' => [38, 1], 'alto' => [95, 3], 'aberta' => [400, 5],
]);

it('aceita as sete faixas do exemplo da especificação', function () {
    $brackets = AgingBrackets::from([
        ['from' => 1, 'to' => 30], ['from' => 31, 'to' => 60], ['from' => 61, 'to' => 90], ['from' => 91, 'to' => 120],
        ['from' => 121, 'to' => 150], ['from' => 151, 'to' => 180], ['from' => 181, 'to' => null],
    ]);

    expect($brackets->brackets)->toHaveCount(7);
});

it('recusa faixas inválidas, com o motivo', function (array $input, string $message) {
    expect(fn () => AgingBrackets::from($input))->toThrow(InvalidBrackets::class, $message);
})->with([
    // R18: 1–30 e 25–60 -> "faixas sobrepostas: 25 a 30".
    'sobrepostas' => [[['from' => 1, 'to' => 30], ['from' => 25, 'to' => null]], 'faixas sobrepostas: 25 a 30'],
    'buraco' => [[['from' => 1, 'to' => 30], ['from' => 40, 'to' => null]], 'buraco entre as faixas: 31 a 39'],
    'não começa em 1' => [[['from' => 5, 'to' => null]], 'as faixas começam em 1 dia de atraso'],
    'última fechada' => [[['from' => 1, 'to' => 30]], 'a última faixa deve ser aberta'],
    'aberta no meio' => [[['from' => 1, 'to' => null], ['from' => 31, 'to' => null]], 'só a última faixa pode ser aberta'],
    'vazia' => [[], 'informe ao menos uma faixa'],
]);

it('gera a expressão SQL com os limites das faixas', function () {
    $sql = AgingBrackets::from(TenantSettings::DEFAULT_BRACKETS)->sqlIndex('days');

    expect($sql)->toContain('when days between 1 and 30 then 0')->toContain('when days >= 361 then 5');
});

it('grava as novas faixas com histórico e recusa as inválidas sem mexer nas atuais', function () {
    $tenant = makeTenant();
    $user = makeUser($tenant);
    $service = new SettingsService;

    $service->updateBrackets($tenant, [['from' => 1, 'to' => 30], ['from' => 31, 'to' => null]], $user);
    expect($tenant->settings->fresh()->aging_brackets)->toHaveCount(2)
        ->and(Change::where('event', 'brackets_changed')->where('user_id', $user->id)->count())->toBe(1);

    expect(fn () => $service->updateBrackets($tenant, [['from' => 1, 'to' => 30], ['from' => 25, 'to' => null]], $user))
        ->toThrow(InvalidBrackets::class, 'faixas sobrepostas: 25 a 30');
    expect($tenant->settings->fresh()->aging_brackets)->toHaveCount(2);
});

it('registra a mudança do tratamento dos títulos a vencer', function () {
    $tenant = makeTenant();
    $user = makeUser($tenant);

    (new SettingsService)->updateUpcomingDisplay($tenant, UpcomingDisplay::Summed, $user);

    expect($tenant->settings->fresh()->upcoming_display)->toBe(UpcomingDisplay::Summed)
        ->and(Change::where('event', 'upcoming_display_changed')->count())->toBe(1);
});
