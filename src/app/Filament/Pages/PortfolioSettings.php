<?php

namespace App\Filament\Pages;

use App\Enums\Permission;
use App\Enums\UpcomingDisplay;
use App\Models\Tenant;
use App\Portfolio\InvalidBrackets;
use App\Portfolio\SettingsService;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Forms\Components\Radio;
use Filament\Forms\Components\Repeater;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Actions;
use Filament\Schemas\Components\EmbeddedSchema;
use Filament\Schemas\Components\Form;
use Filament\Schemas\Components\Utilities\Set;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;

/** Configuração da carteira do credor: faixas de atraso (R18) e tratamento dos títulos a vencer (R20). */
class PortfolioSettings extends Page
{
    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedCog6Tooth;

    protected static ?string $navigationLabel = 'Configuração';

    protected static ?string $title = 'Configuração da carteira';

    protected static ?string $slug = 'configuracao';

    protected static ?int $navigationSort = 40;

    protected string $view = 'filament-panels::pages.page';

    /** @var array<string, mixed>|null */
    public ?array $data = [];

    #[\Override]
    public static function canAccess(): bool
    {
        return Gate::allows('configure', Tenant::class);
    }

    public function mount(): void
    {
        $tenant = $this->tenants()->first();
        $this->form->fill($this->stateFor($tenant));
    }

    public function defaultForm(Schema $schema): Schema
    {
        return $schema->statePath('data');
    }

    public function form(Schema $schema): Schema
    {
        return $schema->components([
            Select::make('tenant_id')->label('Credor')
                ->options($this->tenants()->pluck('name', 'id')->all())
                ->live()
                ->afterStateUpdated(function ($state, Set $set) {
                    foreach ($this->stateFor(Tenant::find($state)) as $key => $value) {
                        $set($key, $value);
                    }
                })
                ->visible($this->tenants()->count() > 1)
                ->required(),
            Repeater::make('brackets')->label('Faixas de atraso (dias)')
                ->helperText('Começam em 1 dia, sem buraco nem sobreposição; a última é aberta (deixe o fim vazio).')
                ->schema([
                    TextInput::make('from')->label('De')->numeric()->required(),
                    TextInput::make('to')->label('Até')->numeric(),
                ])
                ->columns(2)->defaultItems(1)->addActionLabel('Adicionar faixa')->reorderable(false),
            Radio::make('upcoming_display')->label('Títulos a vencer')
                ->options([
                    UpcomingDisplay::Separate->value => 'Separado: coluna própria nos totais e na ficha, fora das faixas',
                    UpcomingDisplay::Summed->value => 'Somado: entra no total em cobrança; o vencido continua visível à parte',
                    UpcomingDisplay::DetailOnly->value => 'Só na ficha: fora dos totais',
                ])
                ->required(),
        ]);
    }

    #[\Override]
    public function content(Schema $schema): Schema
    {
        return $schema->components([
            Form::make([EmbeddedSchema::make('form')])
                ->id('form')
                ->livewireSubmitHandler('save')
                ->footer([Actions::make([Action::make('save')->label('Salvar')->submit('save')])]),
        ]);
    }

    public function save(): void
    {
        $data = $this->form->getState();
        $tenant = Tenant::findOrFail($data['tenant_id'] ?? $this->tenants()->first()->id);
        Gate::authorize('updateSettings', $tenant);

        $service = app(SettingsService::class);
        try {
            $service->updateBrackets($tenant, array_values($data['brackets']), Auth::user());
        } catch (InvalidBrackets $e) {
            // As faixas anteriores continuam valendo (R18).
            Notification::make()->title('Faixas não salvas')->body(ucfirst($e->getMessage()).'. As faixas anteriores continuam valendo.')->danger()->send();

            return;
        }
        $service->updateUpcomingDisplay($tenant, UpcomingDisplay::from($data['upcoming_display']), Auth::user());

        Notification::make()->title('Configuração salva')->success()->send();
    }

    /** @return array<string, mixed> */
    private function stateFor(?Tenant $tenant): array
    {
        if ($tenant === null) {
            return [];
        }
        $settings = $tenant->settings;

        return [
            'tenant_id' => $tenant->id,
            'brackets' => array_map(fn ($b) => ['from' => $b['from'], 'to' => $b['to']], $settings->aging_brackets),
            'upcoming_display' => $settings->upcoming_display->value,
        ];
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->with('settings')->whereIn('id', Auth::user()->tenantIdsWith(Permission::ChangeSettings) ?: [0])->orderBy('name')->get();
    }
}
