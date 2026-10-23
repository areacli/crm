<?php

namespace App\Livewire;

use App\Contacts\ContactAttemptService;
use App\Contacts\ContactRefused;
use App\Demo\DemoMode;
use App\Enums\ContactChannel;
use App\Enums\Permission;
use App\Enums\ReturnRule;
use App\Models\ContactAttempt;
use App\Models\ContactResult;
use App\Models\Contract;
use App\Models\Customer;
use Filament\Actions\Action;
use Filament\Actions\Concerns\InteractsWithActions;
use Filament\Actions\Contracts\HasActions;
use Filament\Forms\Components\DateTimePicker;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Schemas\Concerns\InteractsWithSchemas;
use Filament\Schemas\Contracts\HasSchemas;
use Filament\Tables\Columns\TextColumn;
use Filament\Tables\Concerns\InteractsWithTable;
use Filament\Tables\Contracts\HasTable;
use Filament\Tables\Table;
use Illuminate\Contracts\View\View;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;
use Livewire\Component;

/**
 * Acionamentos de um cliente na ficha (R69 a R75): histórico do mais recente ao mais antigo, 20 por vez, o formulário de
 * registro e a anulação com motivo. As regras são do `ContactAttemptService`; este componente só monta a tela.
 */
final class CustomerContactAttempts extends Component implements HasActions, HasSchemas, HasTable
{
    use InteractsWithActions, InteractsWithSchemas, InteractsWithTable;

    public int $customerId;

    private function customer(): Customer
    {
        $customer = Customer::query()->findOrFail($this->customerId);
        Gate::authorize('view', $customer);

        return $customer;
    }

    public function table(Table $table): Table
    {
        $customer = $this->customer();
        $tenantId = $customer->tenant_id;

        return $table
            ->query(fn (): Builder => ContactAttempt::query()->where('customer_id', $this->customerId)->with(['result', 'user', 'contract', 'voidedBy']))
            ->heading('Acionamentos')
            ->defaultSort('contacted_at', 'desc')
            ->headerActions([
                Action::make('record')->label('Registrar acionamento')->icon('heroicon-o-phone')
                    ->visible(fn () => Auth::user()->hasPermission(Permission::RecordContactAttempts, $tenantId) && Auth::user()->hasPermission(Permission::ViewPortfolio, $tenantId))
                    ->modalHeading('Registrar acionamento')
                    ->modalDescription('Registre só o que for necessário para a cobrança.'.(DemoMode::enabled() ? ' Na demonstração, o texto e o contato digitados são trocados por um texto fictício.' : ''))
                    ->schema($this->form($customer))
                    ->action(fn (array $data) => $this->record($data)),
            ])
            ->columns([
                TextColumn::make('contacted_at')->label('Contato')->dateTime('d/m/Y H:i')->sortable(),
                TextColumn::make('channel')->label('Canal')->badge(),
                TextColumn::make('contact_used')->label('Contato usado')->placeholder('—'),
                TextColumn::make('result.name')->label('Resultado')->description(fn (ContactAttempt $r) => $r->result_type->getLabel()),
                TextColumn::make('contract.code')->label('Contrato')->placeholder('—'),
                TextColumn::make('return_at')->label('Retorno')->dateTime('d/m/Y H:i')->placeholder('—'),
                // Texto puro (R72): a coluna escapa o conteúdo; as quebras de linha ficam por CSS, sem interpretar nada.
                TextColumn::make('text')->label('Texto')->wrap()->placeholder('—')->extraAttributes(['style' => 'white-space: pre-line; min-width: 14rem']),
                TextColumn::make('user.name')->label('Registrado por')->placeholder('—')->description(fn (ContactAttempt $r) => 'em '.$r->created_at->format('d/m/Y H:i')),
                TextColumn::make('void_reason')->label('Anulação')->placeholder('—')->wrap()
                    ->formatStateUsing(fn (ContactAttempt $r, $state) => $r->isVoided() ? 'Anulado: '.$state : '—')
                    ->description(fn (ContactAttempt $r) => $r->isVoided() ? 'por '.($r->voidedBy?->name ?? '—').' em '.$r->voided_at->format('d/m/Y H:i') : null),
            ])
            ->recordClasses(fn (ContactAttempt $r) => $r->isVoided() ? 'opacity-60' : null)
            ->recordActions([
                Action::make('void')->label('Anular')->icon('heroicon-o-no-symbol')->color('danger')
                    ->authorize('void')
                    ->modalDescription('O acionamento continua no histórico, marcado como anulado. A anulação não pode ser desfeita.')
                    ->schema([Textarea::make('reason')->label('Motivo da anulação')->required()->maxLength(300)])
                    ->action(fn (ContactAttempt $record, array $data) => $this->void($record, $data)),
            ])
            ->emptyStateHeading('Nenhum acionamento registrado');
    }

    /** @return list<mixed> */
    private function form(Customer $customer): array
    {
        $tenantId = $customer->tenant_id;
        $rule = fn (?int $id) => $id ? ContactResult::query()->where('tenant_id', $tenantId)->find($id)?->return_rule : null;

        return [
            Select::make('channel')->label('Canal')->options(ContactChannel::class)->required(),
            Select::make('result_id')->label('Resultado')->required()->live()
                ->options(fn () => ContactResult::query()->where('tenant_id', $tenantId)->where('active', true)->orderBy('position')->pluck('name', 'id')->all()),
            Select::make('contract_id')->label('Contrato (opcional)')->live()
                ->options(fn () => Contract::query()->where('tenant_id', $tenantId)->whereHas('customers', fn ($q) => $q->whereKey($customer->id))->get()
                    ->mapWithKeys(fn (Contract $c) => [$c->id => $c->code ?? 'Sem código informado'])->all())
                ->helperText(function ($get) use ($customer): ?string {
                    $contract = $get('contract_id') ? Contract::query()->with('customers')->find($get('contract_id')) : null;
                    if ($contract === null) {
                        return null;
                    }
                    // R69c: o responsável financeiro é só uma sugestão de tela; nada é bloqueado.
                    $responsibles = $contract->financialResponsibles();
                    if ($responsibles->isEmpty() || $responsibles->contains('id', $customer->id)) {
                        return null;
                    }

                    return 'O responsável financeiro deste contrato é '.$responsibles->pluck('name')->implode(', ').'.';
                }),
            // R71: o contato vem da ficha ou é digitado; o digitado fica só no acionamento.
            TextInput::make('contact_used')->label('Contato usado')->maxLength(300)
                ->datalist(array_values(array_filter([$customer->phone, $customer->email])))
                ->helperText('Escolha o da ficha ou digite outro; o digitado fica só neste acionamento.'),
            DateTimePicker::make('contacted_at')->label('Data e hora do contato')->seconds(false)->default(now())
                ->maxDate(now())->minDate(now()->subDays(ContactAttemptService::MAX_PAST_DAYS))
                ->helperText('Padrão: agora. Até '.ContactAttemptService::MAX_PAST_DAYS.' dias atrás.')->required(),
            DateTimePicker::make('return_at')->label('Retorno combinado')->seconds(false)
                ->visible(fn ($get) => $rule((int) $get('result_id')) !== ReturnRule::NotAllowed)
                ->required(fn ($get) => $rule((int) $get('result_id')) === ReturnRule::Required),
            Textarea::make('text')->label('Texto')->maxLength(ContactAttemptService::MAX_TEXT)->rows(4)
                ->helperText('Texto puro, até '.ContactAttemptService::MAX_TEXT.' caracteres. Registre só o necessário para a cobrança.'),
        ];
    }

    /** @param  array<string, mixed>  $data */
    private function record(array $data): void
    {
        $customer = $this->customer();
        if (DemoMode::enabled()) {
            // O que o visitante digita não fica gravado nem visível aos outros.
            $known = array_filter([$customer->phone, $customer->email]);
            if (! empty($data['text'])) {
                $data['text'] = 'texto descartado na demonstração';
            }
            if (! empty($data['contact_used']) && ! in_array($data['contact_used'], $known, true)) {
                $data['contact_used'] = 'contato descartado na demonstração';
            }
        }
        try {
            app(ContactAttemptService::class)->record(Auth::user(), $customer, $data);
        } catch (ContactRefused $e) {
            Notification::make()->title($e->getMessage())->danger()->send();

            return;
        }
        Notification::make()->title('Acionamento registrado')->success()->send();
        $this->resetTable();
    }

    /** @param  array<string, mixed>  $data */
    private function void(ContactAttempt $attempt, array $data): void
    {
        $reason = DemoMode::enabled() ? 'motivo descartado na demonstração' : (string) $data['reason'];
        try {
            app(ContactAttemptService::class)->void(Auth::user(), $attempt, $reason);
        } catch (ContactRefused $e) {
            Notification::make()->title($e->getMessage())->danger()->send();

            return;
        }
        Notification::make()->title('Acionamento anulado')->success()->send();
    }

    public function render(): View
    {
        return view('livewire.customer-contact-attempts');
    }
}
