<?php

namespace App\Filament\Pages;

use App\Demo\DemoFiles;
use App\Demo\DemoMode;
use App\Enums\ImportMode;
use App\Enums\Permission;
use App\Filament\Resources\PaymentImports\PaymentImportResource;
use App\Import\ImportRefused;
use App\Import\ImportService;
use App\Models\Import;
use App\Models\Tenant;
use App\Payments\PaymentColumns;
use BackedEnum;
use Filament\Actions\Action;
use Filament\Forms\Components\FileUpload;
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

/** Envio da planilha de pagamentos (R47, R48): escolhe o credor e o arquivo; a conferência roda em segundo plano. */
class ImportPayments extends Page
{
    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedBanknotes;

    protected static ?string $navigationLabel = 'Importar pagamentos';

    protected static ?string $title = 'Importar pagamentos';

    protected static ?string $slug = 'importar-pagamentos';

    protected static ?int $navigationSort = 32;

    /** 'payments' ou 'reversals': as duas telas só mudam o tipo, as colunas e os textos. */
    protected static string $kind = 'payments';

    protected string $view = 'filament-panels::pages.page';

    /** @var array<string, mixed>|null */
    public ?array $data = [];

    #[\Override]
    public static function canAccess(): bool
    {
        return Gate::allows('createPayments', Import::class);
    }

    public function mount(): void
    {
        $tenants = $this->tenants();
        $this->form->fill(['tenant_id' => $tenants->count() === 1 ? $tenants->first()->id : null]);
    }

    public function defaultForm(Schema $schema): Schema
    {
        return $schema->statePath('data');
    }

    public function form(Schema $schema): Schema
    {
        return $schema->components([
            // O credor é um campo do envio (MT-8): só aparece se houver mais de um.
            Select::make('tenant_id')->label('Credor')
                ->options($this->tenants()->pluck('name', 'id')->all())
                ->required()->visible($this->tenants()->count() > 1),
            FileUpload::make('file')->label('Arquivo CSV')
                ->helperText('Separador ponto e vírgula, UTF-8 ou Windows-1252, até 50 MB e 200.000 linhas.'.(DemoMode::enabled() ? ' Na demonstração, seu arquivo é descartado sem ser lido e trocado por um arquivo fictício.' : ''))
                ->disk('local')->directory('uploads')
                ->acceptedFileTypes(['text/csv', 'text/plain', 'application/vnd.ms-excel', 'application/csv'])
                ->maxSize(52429)
                ->required(),
        ]);
    }

    #[\Override]
    public function content(Schema $schema): Schema
    {
        return $schema->components([
            View::make('filament.imports.columns')->viewData(['columns' => PaymentColumns::for(static::$kind)]),
            Form::make([EmbeddedSchema::make('form')])
                ->id('form')
                ->livewireSubmitHandler('send')
                ->footer([Actions::make([Action::make('send')->label('Enviar e conferir')->submit('send')])]),
        ]);
    }

    /** Planilha-modelo no formato aceito (como a R44). */
    protected function getHeaderActions(): array
    {
        return [
            Action::make('template')->label('Baixar a planilha-modelo')->icon('heroicon-o-arrow-down-tray')->color('gray')
                ->action(fn () => response()->streamDownload(
                    fn () => print (PaymentColumns::templateCsv(static::$kind)),
                    static::$kind === 'payments' ? 'planilha-modelo-pagamentos.csv' : 'planilha-modelo-estornos.csv',
                    ['Content-Type' => 'text/csv; charset=UTF-8'],
                )),
        ];
    }

    public function send(): void
    {
        $data = $this->form->getState();
        $user = Auth::user();

        $tenant = Tenant::findOrFail($data['tenant_id'] ?? $this->tenants()->first()->id);
        Gate::authorize('uploadPayments', [Import::class, $tenant]);

        $stored = is_array($data['file']) ? array_values($data['file'])[0] : $data['file'];

        // Na demonstração, o arquivo do visitante é descartado sem ser lido e trocado por um arquivo fictício montado da carteira do dia.
        $source = Storage::disk('local')->path($stored);
        $original = basename((string) $stored);
        if (DemoMode::enabled()) {
            $channel = $tenant->paymentChannels()->where('active', true)->orderBy('id')->value('code') ?? '';
            $source = static::$kind === 'reversals' ? DemoFiles::reversals($tenant) : DemoFiles::payments($tenant, $channel);
            $original = DemoFiles::NAME;
        }

        try {
            $import = app(ImportService::class)->start(
                $tenant, $user, $source, ImportMode::Incremental, $original, static::$kind,
            );
        } catch (ImportRefused $e) {
            Notification::make()->title('Não foi possível iniciar a importação')->body(ucfirst($e->getMessage()).'.')->danger()->send();

            return;
        } finally {
            Storage::disk('local')->delete($stored);
            if (DemoMode::enabled()) {
                @unlink($source);
            }
        }

        $this->redirect(PaymentImportResource::getUrl('view', ['record' => $import]));
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->whereIn('id', Auth::user()->tenantIdsWith(Permission::UploadPayments) ?: [0])->orderBy('name')->get();
    }
}
