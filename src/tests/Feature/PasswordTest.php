<?php

use App\Access\TemporaryPassword;
use App\Filament\Pages\ChangePassword;
use App\Models\User;
use Illuminate\Support\Facades\Hash;
use Livewire\Livewire;

it('gera senha temporária no formato combinado', function () {
    expect(TemporaryPassword::generate())->toMatch('/^[A-Za-z2-9]{4}(-[A-Za-z2-9]{4}){3}$/');
});

it('leva quem tem senha temporária só à tela de definir a senha (R38)', function () {
    $tenant = makeTenant();
    $user = makeUser($tenant, 'joana@exemplo.com.br');
    $user->forceFill(['temporary_password_until' => now()->addHours(10)])->save();

    $this->actingAs($user)->get('/')->assertRedirect(ChangePassword::getUrl());
    $this->actingAs($user)->get(ChangePassword::getUrl())->assertOk()->assertSee('senha temporária');
});

it('recusa o login com senha temporária vencida (R37)', function () {
    $tenant = makeTenant();
    $user = makeUser($tenant, 'joana@exemplo.com.br');
    $user->forceFill(['temporary_password_until' => now()->subHour()])->save();

    expect($user->fresh()->canAccessPanel(Filament\Facades\Filament::getPanel('crm')))->toBeFalse();
    $this->actingAs($user)->get('/')->assertRedirect();
});

it('troca a senha com a atual, recusa a igual e a fraca (R38, R39)', function () {
    $tenant = makeTenant();
    $user = makeUser($tenant, 'joana@exemplo.com.br');
    $user->forceFill(['password' => 'Temporaria-1234', 'temporary_password_until' => now()->addHours(10)])->save();
    $this->actingAs($user);

    Livewire::test(ChangePassword::class)
        ->fillForm(['current_password' => 'Temporaria-1234', 'password' => 'Temporaria-1234', 'password_confirmation' => 'Temporaria-1234'])
        ->call('save')->assertHasErrors();
    Livewire::test(ChangePassword::class)
        ->fillForm(['current_password' => 'Temporaria-1234', 'password' => '123456789012', 'password_confirmation' => '123456789012'])
        ->call('save')->assertHasErrors();
    Livewire::test(ChangePassword::class)
        ->fillForm(['current_password' => 'errada', 'password' => 'Outra-senha-forte-9', 'password_confirmation' => 'Outra-senha-forte-9'])
        ->call('save')->assertHasErrors();
    Livewire::test(ChangePassword::class)
        ->fillForm(['current_password' => 'Temporaria-1234', 'password' => 'Outra-senha-forte-9', 'password_confirmation' => 'Outra-senha-forte-9'])
        ->call('save')->assertHasNoErrors();

    $user = User::find($user->id);
    expect($user->temporary_password_until)->toBeNull()
        ->and(Hash::check('Outra-senha-forte-9', $user->password))->toBeTrue();
    $this->assertDatabaseHas('access_events', ['event' => 'password_changed', 'user_id' => $user->id]);
});
