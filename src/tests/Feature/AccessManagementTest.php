<?php

use App\Access\AccessManager;
use App\Access\AccessRefused;
use App\Access\ProfileManager;
use App\Enums\Permission;
use App\Filament\Resources\Memberships\Pages\ListMemberships;
use App\Filament\Resources\Profiles\Pages\CreateProfile;
use App\Filament\Resources\Profiles\Pages\ListProfiles;
use App\Models\Membership;
use App\Models\Profile;
use App\Models\User;
use Livewire\Livewire;

function operatorProfile($tenant): Profile
{
    return Profile::factory()->allowing([Permission::ViewPortfolio, Permission::RecordContactAttempts])->create(['tenant_id' => $tenant->id, 'name' => 'Operador']);
}

it('mostra o menu conforme a permissão e recusa o endereço direto com registro (R33)', function () {
    $tenant = makeTenant();
    operatorProfile($tenant);
    $joana = makeUser($tenant, 'joana@exemplo.com.br', 'Operador');

    $this->actingAs($joana)->get('/usuarios')->assertForbidden();
    $this->actingAs($joana)->get('/perfis')->assertForbidden();
    $this->assertDatabaseHas('access_events', ['event' => 'permission_denied', 'user_id' => $joana->id]);
});

it('cria usuário com senha temporária única e registra sem a senha (R36, R37, R42)', function () {
    $tenant = makeTenant();
    $profile = operatorProfile($tenant);
    $ana = makeUser($tenant, 'ana@exemplo.com.br');

    [$user, $password] = app(AccessManager::class)->createUser($ana, $tenant, 'Joana.Souza@Credor.example', 'Joana Souza', $profile);

    expect($user->email)->toBe('joana.souza@credor.example')
        ->and($user->mustChangePassword())->toBeTrue()
        ->and($user->temporary_password_until->diffInHours(now(), true))->toBeBetween(71, 72.1)
        ->and(Membership::where('user_id', $user->id)->where('tenant_id', $tenant->id)->exists())->toBeTrue();
    $event = DB::table('access_events')->where('event', 'user_created')->first();
    expect($event->details)->not->toContain($password)->and($event->actor_id)->toBe($ana->id);
});

it('muda o perfil, vale na próxima ação e proíbe mudar o próprio (R33, PD7)', function () {
    $tenant = makeTenant();
    $operator = operatorProfile($tenant);
    $manager = Profile::where('tenant_id', $tenant->id)->where('name', 'Gestor')->first();
    $ana = makeUser($tenant, 'ana@exemplo.com.br');
    $joana = makeUser($tenant, 'joana@exemplo.com.br', 'Operador');
    $svc = app(AccessManager::class);

    expect($joana->fresh()->hasAnyPermission(Permission::UploadImports))->toBeFalse();
    $svc->changeProfile($ana, $joana->memberships()->first(), $manager);
    expect(User::find($joana->id)->hasAnyPermission(Permission::UploadImports))->toBeTrue();

    expect(fn () => $svc->changeProfile($ana, $ana->memberships()->first(), $operator))->toThrow(AccessRefused::class);
});

it('protege contra ficar sem quem gerencie, por credor (R41)', function () {
    $alfa = makeTenant('Alfa');
    $beta = makeTenant('Beta');
    $operator = operatorProfile($alfa);
    $ana = makeUser($alfa, 'ana@exemplo.com.br');
    $beta2 = Membership::factory()->create(['user_id' => $ana->id, 'tenant_id' => $beta->id, 'profile_id' => Profile::where('tenant_id', $beta->id)->first()->id]);
    $outra = makeUser($beta, 'outra@exemplo.com.br');
    $pm = app(ProfileManager::class);
    $svc = app(AccessManager::class);

    // Ana é a única com as duas permissões na Alfa; ser gestora na Beta não cobre.
    $outroAlfa = makeUser($alfa, 'op@exemplo.com.br');
    $outroAlfa->memberships()->update(['profile_id' => $operator->id]);
    $gestorAlfa = Profile::where('tenant_id', $alfa->id)->where('name', 'Gestor')->first();
    $perms = array_values(array_diff($gestorAlfa->permissions, [Permission::ManageProfiles->value]));
    $helper = User::factory()->create();
    Membership::factory()->create(['user_id' => $helper->id, 'tenant_id' => $alfa->id, 'profile_id' => Profile::factory()->allowing([Permission::ManageProfiles, Permission::ViewPortfolio])->create(['tenant_id' => $alfa->id, 'name' => 'Perfis'])->id]);

    expect(fn () => $pm->update($helper, $gestorAlfa, 'Gestor', $perms))->toThrow(AccessRefused::class, 'Ao menos um usuário ativo');
    // Desativar a única gestora também é recusado.
    expect(fn () => $svc->setActive($helper, $ana->memberships()->where('tenant_id', $alfa->id)->first(), false))->toThrow(AccessRefused::class);
});

it('recusa perfil com permissões sem consultar e administrar sem negociar (PD6, AC7)', function () {
    $tenant = makeTenant();
    $ana = makeUser($tenant, 'ana@exemplo.com.br');
    $pm = app(ProfileManager::class);

    expect(fn () => $pm->create($ana, $tenant, 'X', [Permission::RecordContactAttempts->value]))->toThrow(AccessRefused::class, 'Consultar');
    expect(fn () => $pm->create($ana, $tenant, 'Y', [Permission::ViewPortfolio->value, Permission::AdministerAgreements->value]))->toThrow(AccessRefused::class, 'Negociar');
    expect($pm->create($ana, $tenant, 'Z', [Permission::ViewPortfolio->value, Permission::UploadImports->value]))->toBeInstanceOf(Profile::class);
});

it('apaga perfil só sem usuários (R35)', function () {
    $tenant = makeTenant();
    $operator = operatorProfile($tenant);
    $ana = makeUser($tenant, 'ana@exemplo.com.br');
    makeUser($tenant, 'joana@exemplo.com.br', 'Operador');
    $pm = app(ProfileManager::class);

    expect(fn () => $pm->delete($ana, $operator))->toThrow(AccessRefused::class, 'em uso por 1 usuário');
    $free = Profile::factory()->create(['tenant_id' => $tenant->id, 'name' => 'Vazio']);
    $pm->delete($ana, $free);
    expect(Profile::find($free->id))->toBeNull();
});

it('liga pela tela quem já existe em outro credor, com aviso, sem redefinir nome ou senha (R36a, R40)', function () {
    $alfa = makeTenant('Alfa');
    $beta = makeTenant('Beta');
    $ana = makeUser($alfa, 'ana@exemplo.com.br');
    $marta = makeUser($beta, 'marta@grupo.example', 'Gestor');
    $profile = operatorProfile($alfa);
    $svc = app(AccessManager::class);

    $membership = $svc->linkExisting($ana, $alfa, $marta, $profile);
    expect($membership->active)->toBeTrue()
        ->and($marta->notifications()->count())->toBe(1)
        ->and($svc->isPersonalEditable($membership))->toBeFalse();
    expect(fn () => $svc->resetPassword($ana, $membership))->toThrow(AccessRefused::class);
    expect(fn () => $svc->rename($ana, $membership, 'Outro'))->toThrow(AccessRefused::class);

    // Desativar o vínculo na Alfa não tira a Marta da Beta.
    $svc->setActive($ana, $membership, false);
    expect($marta->fresh()->canAccessPanel(Filament\Facades\Filament::getPanel('crm')))->toBeTrue()
        ->and($marta->fresh()->hasAnyPermission(Permission::ViewPortfolio))->toBeTrue()
        ->and($marta->fresh()->tenantIdsWith(Permission::ViewPortfolio))->toBe([$beta->id]);
});

it('não mostra nem permite agir sobre usuários de outro credor, nem por link (MT-5, V10)', function () {
    $alfa = makeTenant('Alfa');
    $beta = makeTenant('Beta');
    $ana = makeUser($alfa, 'ana@exemplo.com.br');
    $outro = makeUser($beta, 'beta@exemplo.com.br');
    $other = $outro->memberships()->first();

    Livewire::actingAs($ana)->test(ListMemberships::class)
        ->assertCanSeeTableRecords($ana->memberships)->assertCanNotSeeTableRecords([$other]);
    expect(fn () => app(AccessManager::class)->changeProfile($ana, $other, $other->profile))->toThrow(AccessRefused::class);
    $this->assertDatabaseHas('access_events', ['event' => 'permission_denied', 'user_id' => $ana->id]);
});

it('o gestor não vê a opção de desativar a si mesmo (R36)', function () {
    $tenant = makeTenant();
    $ana = makeUser($tenant, 'ana@exemplo.com.br');
    $joana = makeUser($tenant, 'joana@exemplo.com.br');

    Livewire::actingAs($ana)->test(ListMemberships::class)
        ->assertTableActionHidden('deactivate', $ana->memberships()->first())
        ->assertTableActionVisible('deactivate', $joana->memberships()->first());
});

it('cria perfil pela tela, com as permissões escolhidas', function () {
    $tenant = makeTenant();
    $ana = makeUser($tenant, 'ana@exemplo.com.br');

    Livewire::actingAs($ana)->test(CreateProfile::class)
        ->fillForm(['name' => 'Analista de carga', 'permissions' => ['view_portfolio', 'upload_imports']])
        ->call('create')->assertHasNoFormErrors();
    expect(Profile::where('name', 'Analista de carga')->first()->permissions)->toBe(['view_portfolio', 'upload_imports']);
    Livewire::actingAs($ana)->test(ListProfiles::class)->assertSee('Analista de carga');
});

it('o comando cria com senha temporária, liga a outro credor, renomeia e lista (R43)', function () {
    $alfa = makeTenant('Alfa');
    makeTenant('Beta');

    $this->artisan('crm:user', ['action' => 'create', 'email' => 'nova@exemplo.com.br', '--tenant' => 'Alfa'])
        ->expectsOutputToContain('Senha temporária')->assertSuccessful();
    $user = User::where('email', 'nova@exemplo.com.br')->first();
    expect($user->mustChangePassword())->toBeTrue();

    $this->artisan('crm:user', ['action' => 'link', 'email' => 'nova@exemplo.com.br', '--tenant' => 'Beta'])->assertSuccessful();
    $this->artisan('crm:user', ['action' => 'rename', 'email' => 'nova@exemplo.com.br', '--name' => 'Nova Pessoa'])->assertSuccessful();
    expect($user->fresh()->name)->toBe('Nova Pessoa')->and($user->memberships()->count())->toBe(2);
    $this->artisan('crm:user', ['action' => 'list'])->expectsOutputToContain('nova@exemplo.com.br')->assertSuccessful();

    $this->artisan('crm:user', ['action' => 'reset-password', 'email' => 'nova@exemplo.com.br'])
        ->expectsOutputToContain('Senha temporária')->assertSuccessful();
});
