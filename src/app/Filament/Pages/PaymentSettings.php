<?php

namespace App\Filament\Pages;

use App\Enums\PartialPaymentPolicy;
use App\Enums\Permission;
use App\Enums\ReversalMonthPolicy;
use App\Enums\WithdrawnPaymentPolicy;
use App\Enums\WithdrawnReversalPolicy;
use App\Filament\Clusters\SettingsCluster;
use App\Models\Change;
use App\Models\Tenant;
use Filament\Actions\Action;
use Filament\Forms\Components\Radio;
use Filament\Forms\Components\Select;
use Filament\Notifications\Notification;
use Filament\Pages\Page;
use Filament\Schemas\Components\Actions;
use Filament\Schemas\Components\EmbeddedSchema;
use Filament\Schemas\Components\Form;
use Filament\Schemas\Components\Utilities\Set;
use Filament\Schemas\Schema;
use Illuminate\Support\Collection;
use Illuminate\Support\Facades\Auth;
use Illuminate\Support\Facades\Gate;

/** Políticas do credor para pagamentos e estornos (R46, R46a, R62a, R64): permissão 14, no credor escolhido. */
class PaymentSettings extends Page
{
    protected static ?string $cluster = SettingsCluster::class;

    protected static ?string $navigationLabel = 'Políticas de pagamento';

    protected static ?string $title = 'Políticas de pagamento e estorno';

    protected static ?string $slug = 'pagamentos';

    protected static ?int $navigationSort = 3;

    protected string $view = 'filament-panels::pages.page';

    /** @var array<string, mixed>|null */
    public ?array $data = [];

    private const array FIELDS = [
        'partial_payment_policy' => PartialPaymentPolicy::class,
        'withdrawn_payment_policy' => WithdrawnPaymentPolicy::class,
        'withdrawn_reversal_policy' => WithdrawnReversalPolicy::class,
        'reversal_month_policy' => ReversalMonthPolicy::class,
    ];

    #[\Override]
    public static function canAccess(): bool
    {
        return Gate::allows('configurePayments', Tenant::class);
    }

    public function mount(): void
    {
        $this->form->fill($this->stateFor($this->tenants()->first()));
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
                ->visible($this->tenants()->count() > 1)->required(),
            Radio::make('partial_payment_policy')->label('Pagamento menor que o saldo')->options(PartialPaymentPolicy::class)->required(),
            Radio::make('withdrawn_payment_policy')->label('Pagamento de título retirado')->options(WithdrawnPaymentPolicy::class)->required(),
            Radio::make('withdrawn_reversal_policy')->label('Título retirado, quitado e depois estornado')->options(WithdrawnReversalPolicy::class)->required(),
            Radio::make('reversal_month_policy')->label('Mês em que o estorno desconta do valor recuperado')->options(ReversalMonthPolicy::class)->required(),
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
        Gate::authorize('updatePaymentPolicies', $tenant);

        $settings = $tenant->settings;
        foreach (self::FIELDS as $field => $enum) {
            $new = $data[$field] instanceof $enum ? $data[$field] : $enum::from($data[$field]);
            $before = $settings->{$field}->value;
            if ($before !== $new->value) {
                $settings->{$field} = $new;
                // Cada mudança de política fica registrada: quem, quando, antes e depois (PD4).
                Change::create([
                    'tenant_id' => $tenant->id, 'user_id' => Auth::id(), 'subject_type' => 'settings', 'subject_id' => $tenant->id,
                    'event' => $field.'_changed', 'field' => $field, 'before' => $before, 'after' => $new->value, 'occurred_at' => now(),
                ]);
            }
        }
        $settings->save();

        Notification::make()->title('Políticas salvas')->success()->send();
    }

    /** @return array<string, mixed> */
    private function stateFor(?Tenant $tenant): array
    {
        if ($tenant === null) {
            return [];
        }

        return ['tenant_id' => $tenant->id] + collect(self::FIELDS)->map(fn ($enum, $field) => $tenant->settings->{$field}->value)->all();
    }

    /** @return Collection<int, Tenant> */
    private function tenants()
    {
        return Tenant::query()->with('settings')->whereIn('id', Auth::user()->tenantIdsWith(Permission::ChangeFinancialPolicies) ?: [0])->orderBy('name')->get();
    }
}
