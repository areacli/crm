<?php

namespace App\Filament\Clusters;

use BackedEnum;
use Filament\Clusters\Cluster;
use Filament\Support\Icons\Heroicon;

/**
 * Configuração do credor (padrões de interface, T6): uma entrada no menu e, dentro dela, uma aba por assunto
 * (Políticas da carteira, Canais de recebimento, Políticas de pagamento, Resultados de acionamento). Cada aba é uma
 * página ou um recurso com a própria permissão; a entrada abre a primeira aba que o usuário pode ver.
 */
class SettingsCluster extends Cluster
{
    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedCog6Tooth;

    protected static ?string $navigationLabel = 'Configuração';

    protected static ?string $slug = 'configuracao';

    protected static ?string $clusterBreadcrumb = 'Configuração';

    protected static ?int $navigationSort = 40;

    /** Sem permissão em nenhuma aba, a entrada responde como proibida (R33). */
    #[\Override]
    public static function canAccess(): bool
    {
        return static::canAccessClusteredComponents();
    }
}
