<?php

namespace App\Filament\Pages;

use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Filament\Resources\Imports\ImportResource;
use App\Import\CsvColumns;
use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Models\Import;
use App\Models\Tenant;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Forms\Components\FileUpload;
use Filament\Forms\Components\Radio;
use Filament\Forms\Components\Select;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Actions;
use Filament\Schemas\Components\EmbeddedSchema;
use Filament\Schemas\Components\Form;
use Filament\Schemas\Components\View;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Illuminate\Support\Facades\Storage;

/** Envio da planilha de carteira (R10): escolhe o credor, o modo e o arquivo; a conferência roda em segundo plano. */
class ImportPortfolio extends Page
{
    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedArrowUpTray;

    protected static ?string $navigationLabel = 'Importar carteira';

    protected static ?string $title = 'Importar carteira';

    protected static ?string $slug = 'importar';

    protected static ?int $navigationSort = 30;

    // A página usa só o esquema de conteúdo (content()), sem visão própria.
    protected string $view = 'filament-panels::pages.page';

    /** @var array<string, mixed>|null */
    public ?array $data = [];

    #[\Override]
    public static function canAccess(): bool
    {
        return Gate::allows('create', Import::class);
    }

    public function mount(): void
    {
        $tenants = $this->tenants();
        $this->form->fill([
            'mode' => ImportMode::Incremental->value,
            'tenant_id' => $tenants->count() === 1 ? $tenants->first()->id : null,
        ]);
    }

    public function defaultForm(Schema $schema): Schema
    {
        return $schema->statePath('data');
    }

    public function form(Schema $schema): Schema
    {
        return $schema->components([
            // O credor é um campo do envio, não uma seleção global (MT-8): só aparece se houver mais de um.
            Select::make('tenant_id')->label('Credor')
                ->options($this->tenants()->pluck('name', 'id')->all())
                ->required()
                ->visible($this->tenants()->count() > 1),
            Radio::make('mode')->label('Modo da importação')
                ->options([
                    ImportMode::Incremental->value => 'Incremental: só inclui e atualiza títulos; o que não está no arquivo não muda',
                    ImportMode::FullSync->value => 'Batimento: o arquivo é a carteira inteira; títulos que não estão nele passam a retirados',
                ])
                ->default(ImportMode::Incremental->value)
                ->required(),
            FileUpload::make('file')->label('Arquivo CSV')
                ->helperText('Separador ponto e vírgula, UTF-8 ou Windows-1252, até 50 MB e 200.000 linhas.')
                ->disk('local')->directory('uploads')
                ->acceptedFileTypes(['text/csv', 'text/plain', 'application/vnd.ms-excel', 'application/csv'])
                // 50 MiB. O campo de arquivo do Filament mede no navegador em KB decimais (1 KB = 1.000 bytes) e o servidor
                // em KiB (1.024 bytes): 52.429 KB decimais no navegador equivalem aos 51.200 KiB do servidor (config/livewire.php).
                ->maxSize(52429)
                ->required(),
        ]);
    }

    #[\Override]
    public function content(Schema $schema): Schema
    {
        return $schema->components([
            View::make('filament.imports.columns')->viewData(['columns' => CsvColumns::all()]),
            Form::make([EmbeddedSchema::make('form')])
                ->id('form')
                ->livewireSubmitHandler('send')
                ->footer([
                    Actions::make([
                        Action::make('send')->label('Enviar e conferir')->submit('send'),
                    ]),
                ]),
        ]);
    }

    /** R44: planilha-modelo no formato aceito, com cabeçalho e três linhas fictícias. */
    protected function getHeaderActions(): array
    {
        return [
            Action::make('template')->label('Baixar a planilha-modelo')->icon('heroicon-o-arrow-down-tray')->color('gray')
                ->action(fn () => response()->streamDownload(fn () => print (CsvColumns::templateCsv()), 'planilha-modelo-carteira.csv', ['Content-Type' => 'text/csv; charset=UTF-8'])),
        ];
    }

    public function send(): void
    {
        $data = $this->form->getState();
        $user = Auth::user();

        $tenant = Tenant::findOrFail($data['tenant_id'] ?? $this->tenants()->first()->id);
        Gate::authorize('upload', [Import::class, $tenant]);

        $stored = is_array($data['file']) ? array_values($data['file'])[0] : $data['file'];
        $original = basename((string) $stored);

        try {
            $import = app(ImportService::class)->start(
                $tenant, $user, Storage::disk('local')->path($stored), ImportMode::from($data['mode']), $original,
            );
        } catch (ImportRefused $e) {
            Notification::make()->title('Não foi possível iniciar a importação')->body(ucfirst($e->getMessage()).'.')->danger()->send();

            return;
        } finally {
            Storage::disk('local')->delete($stored);
        }

        $this->redirect(ImportResource::getUrl('view', ['record' => $import]));
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->whereIn('id', Auth::user()->tenantIdsWith(Permission::UploadImports) ?: [0])->orderBy('name')->get();
    }
}
