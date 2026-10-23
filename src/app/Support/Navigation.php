<?php

namespace App\Support;

use App\Enums\Permission;
use App\Models\User;
use Illuminate\Support\Facades\Gate;

/**
 * Menu lateral: cada item aparece se o usuário tem a permissão em pelo menos um credor (P1). A Configuração é um item só,
 * com as abas por assunto dentro (P21), e abre a primeira aba que o usuário pode ver.
 */
final class Navigation
{
    /**
     * @return list<array{title: ?string, items: list<array{label: string, route: string, match: string}>}>
     */
    public static function sections(User $user): array
    {
        $has = fn (Permission ...$p) => collect($p)->contains(fn (Permission $x) => $user->hasAnyPermission($x));
        $sections = [
            ['title' => null, 'items' => [
                ['label' => 'Resumo', 'route' => 'summary', 'match' => '/', 'show' => Gate::forUser($user)->allows('view-summary')],
            ]],
            ['title' => 'Carteira', 'items' => [
                ['label' => 'Clientes', 'route' => 'customers.index', 'match' => 'clientes*', 'show' => $has(Permission::ViewPortfolio)],
                ['label' => 'Acionamentos', 'route' => 'contacts.index', 'match' => 'acionamentos*', 'show' => $has(Permission::ViewPortfolio)],
                ['label' => 'Importar carteira', 'route' => 'imports.create', 'match' => 'importar', 'show' => $has(Permission::UploadImports)],
                ['label' => 'Importações', 'route' => 'imports.index', 'match' => 'importacoes*', 'show' => $has(Permission::UploadImports, Permission::ConfirmImports)],
            ]],
            ['title' => 'Recebimentos', 'items' => [
                ['label' => 'Importar pagamentos', 'route' => 'payments.create', 'match' => 'importar-pagamentos', 'show' => $has(Permission::UploadPayments)],
                ['label' => 'Importar estornos', 'route' => 'reversals.create', 'match' => 'importar-estornos', 'show' => $has(Permission::UploadPayments)],
                ['label' => 'Pagamentos', 'route' => 'payments.index', 'match' => 'pagamentos*', 'show' => $has(Permission::UploadPayments, Permission::ConfirmPayments)],
            ]],
            ['title' => 'Administração', 'items' => [
                ['label' => 'Configuração', 'route' => 'settings', 'match' => 'configuracao*', 'show' => self::firstSettingsTab($user) !== null],
                ['label' => 'Usuários', 'route' => 'users.index', 'match' => 'usuarios*', 'show' => $has(Permission::ManageUsers)],
                ['label' => 'Perfis', 'route' => 'profiles.index', 'match' => 'perfis*', 'show' => $has(Permission::ManageProfiles)],
            ]],
        ];

        return array_values(array_filter(array_map(function (array $section) {
            $section['items'] = array_values(array_filter($section['items'], fn (array $item) => $item['show']));

            return $section['items'] === [] ? null : $section;
        }, $sections)));
    }

    /**
     * As abas da Configuração, na ordem (T6), cada uma com a própria permissão.
     *
     * @return list<array{label: string, route: string}>
     */
    public static function settingsTabs(User $user): array
    {
        $tabs = [
            ['label' => 'Políticas da carteira', 'route' => 'settings.portfolio', 'show' => $user->hasAnyPermission(Permission::ChangeSettings)],
            ['label' => 'Canais de recebimento', 'route' => 'settings.channels', 'show' => $user->hasAnyPermission(Permission::ChangeSettings)],
            ['label' => 'Políticas de pagamento', 'route' => 'settings.payments', 'show' => $user->hasAnyPermission(Permission::ChangeFinancialPolicies)],
            ['label' => 'Resultados de acionamento', 'route' => 'settings.contacts', 'show' => $user->hasAnyPermission(Permission::ManageContactResults)],
        ];

        return array_values(array_map(fn (array $t) => ['label' => $t['label'], 'route' => $t['route']], array_filter($tabs, fn (array $t) => $t['show'])));
    }

    public static function firstSettingsTab(User $user): ?string
    {
        return self::settingsTabs($user)[0]['route'] ?? null;
    }

    /** Primeira tela que o usuário pode abrir, para a entrada (T1) e para a recusa do resumo. */
    public static function firstRoute(User $user): ?string
    {
        foreach (self::sections($user) as $section) {
            foreach ($section['items'] as $item) {
                return $item['route'];
            }
        }

        return null;
    }
}
