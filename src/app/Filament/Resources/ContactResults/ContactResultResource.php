<?php

namespace App\Filament\Resources\ContactResults;

use App\Contacts\ContactRefused;
use App\Contacts\ContactResultManager;
use App\Enums\ContactResultType;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Filament\Clusters\SettingsCluster;
use App\Filament\Resources\ContactResults\Pages\ManageContactResults;
use App\Models\ContactResult;
use App\Models\Tenant;
use Filament\Actions\Action;
use Filament\Actions\EditAction;
use Filament\Forms\Components\Hidden;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Tables\Columns\IconColumn;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Filters\SelectFilter;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/** Resultados de acionamento do credor (R66, R67): uma aba da configuração, com a permissão "gerenciar resultados". */
class ContactResultResource extends Resource
{
    protected static ?string $model = ContactResult::class;

    protected static ?string $cluster = SettingsCluster::class;

    protected static ?string $modelLabel = 'resultado de acionamento';

    protected static ?string $pluralModelLabel = 'resultados de acionamento';

    protected static ?string $navigationLabel = 'Resultados de acionamento';

    protected static ?string $slug = 'acionamentos';

    protected static ?int $navigationSort = 4;

    public static function getEloquentQuery(): Builder
    {
        return ContactResult::query()->visibleTo(Auth::user(), Permission::ManageContactResults);
    }

    #[\Override]
    public static function getTitleCaseModelLabel(): string
    {
        return 'Resultado de acionamento';
    }

    #[\Override]
    public static function getTitleCasePluralModelLabel(): string
    {
        return 'Resultados de acionamento';
    }

    public static function form(Schema $schema): Schema
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageContactResults);

        return $schema->components([
            Select::make('tenant_id')->label('Credor')
                ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                ->required()->disabled(fn (?ContactResult $record) => $record !== null)->dehydrated()
                ->visible(count($ids) > 1),
            Hidden::make('tenant_id')->default($ids[0] ?? null)->visible(count($ids) <= 1),
            TextInput::make('name')->label('Nome')->required()->maxLength(100),
            // O tipo não muda depois de criado, para não alterar o significado dos acionamentos antigos (R66).
            Select::make('type')->label('Tipo')->options(ContactResultType::class)->required()->disabled(fn (?ContactResult $record) => $record !== null)->dehydrated()
                ->helperText('Não muda depois de criado.'),
            Select::make('return_rule')->label('Data de retorno')->options(ReturnRule::class)->required(),
        ]);
    }

    public static function table(Table $table): Table
    {
        $ids = Auth::user()->tenantIdsWith(Permission::ManageContactResults);
        $manager = fn () => app(ContactResultManager::class);
        $run = function (callable $change, ?string $done = null): void {
            try {
                $change();
                if ($done) {
                    Notification::make()->title($done)->success()->send();
                }
            } catch (ContactRefused $e) {
                Notification::make()->title($e->getMessage())->danger()->send();
            }
        };

        return $table
            ->defaultSort('position')
            ->reorderable(false)
            ->columns([
                TextColumn::make('tenant.name')->label('Credor')->visible(count($ids) > 1),
                TextColumn::make('name')->label('Nome')->searchable(),
                TextColumn::make('type')->label('Tipo')->badge(),
                TextColumn::make('return_rule')->label('Retorno'),
                TextColumn::make('attempts_count')->label('Acionamentos')->counts('attempts')->alignEnd(),
                IconColumn::make('active')->label('Ativo')->boolean(),
            ])
            ->filters([
                SelectFilter::make('tenant_id')->label('Credor')
                    ->options(fn () => Tenant::query()->whereIn('id', $ids)->orderBy('name')->pluck('name', 'id')->all())
                    ->visible(count($ids) > 1),
            ])
            ->recordActions([
                Action::make('up')->label('Subir')->icon('heroicon-o-arrow-up')->iconButton()->authorize('update')
                    ->action(fn (ContactResult $record) => $run(fn () => $manager()->move(Auth::user(), $record, -1))),
                Action::make('down')->label('Descer')->icon('heroicon-o-arrow-down')->iconButton()->authorize('update')
                    ->action(fn (ContactResult $record) => $run(fn () => $manager()->move(Auth::user(), $record, 1))),
                EditAction::make()->label('Editar')
                    ->using(function (ContactResult $record, array $data) use ($manager, $run) {
                        $run(fn () => $manager()->update(Auth::user(), $record, $data['name'], ReturnRule::from($data['return_rule'] instanceof ReturnRule ? $data['return_rule']->value : $data['return_rule'])), 'Resultado salvo');

                        return $record->refresh();
                    })->successNotification(null),
                Action::make('deactivate')->label('Desativar')->color('danger')->icon('heroicon-o-no-symbol')->authorize('update')
                    ->visible(fn (ContactResult $record) => $record->active)->requiresConfirmation()
                    ->modalDescription('O resultado some da lista de escolha e continua aparecendo, com o nome que tem, nos acionamentos antigos.')
                    ->action(fn (ContactResult $record) => $run(fn () => $manager()->setActive(Auth::user(), $record, false), 'Resultado desativado')),
                Action::make('reactivate')->label('Reativar')->icon('heroicon-o-check-circle')->authorize('update')
                    ->visible(fn (ContactResult $record) => ! $record->active)
                    ->action(fn (ContactResult $record) => $run(fn () => $manager()->setActive(Auth::user(), $record, true), 'Resultado reativado')),
            ])
            ->emptyStateHeading('Nenhum resultado');
    }

    public static function getPages(): array
    {
        return ['index' => ManageContactResults::route('/')];
    }
}
