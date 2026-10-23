<?php

namespace App\Filament\Resources\Customers\Pages;

use App\Access\AccessRefused;
use App\Demo\DemoMode;
use App\Filament\Resources\Customers\CustomerResource;
use App\Models\Bill;
use App\Models\Contract;
use App\Payments\CreditTransfer;
use App\Support\Money;
use Filament\Actions\Action;
use Filament\Forms\Components\Select;
use Filament\Forms\Components\Textarea;
use Filament\Forms\Components\TextInput;
use Filament\Notifications\Notification;
use Filament\Resources\Pages\ViewRecord;
use Illuminate\Support\Facades\Auth;

class ViewCustomer extends ViewRecord
{
    protected static string $resource = CustomerResource::class;

    /** R55a: transferir crédito entre contratos do mesmo credor (permissão 17). */
    protected function getHeaderActions(): array
    {
        return [
            Action::make('transfer-credit')->label('Transferir crédito')->icon('heroicon-o-arrows-right-left')->color('gray')
                ->authorize('transferCredit')
                ->visible(fn () => Contract::query()->whereIn('id', $this->contractIds())->get()->contains(fn (Contract $c) => $c->creditCents() > 0))
                ->modalDescription('O crédito é do contrato. A transferência move crédito disponível para outro contrato do mesmo credor, com motivo, e fica registrada nos dois contratos.')
                ->schema([
                    Select::make('from')->label('Contrato de origem')->required()
                        ->options(fn () => Contract::query()->whereIn('id', $this->contractIds())->get()->filter(fn (Contract $c) => $c->creditCents() > 0)
                            ->mapWithKeys(fn (Contract $c) => [$c->id => ($c->code ? 'Contrato '.$c->code : 'Sem contrato informado').' — crédito R$ '.Money::format($c->creditCents())])->all()),
                    TextInput::make('to')->label('Código do contrato de destino')->required()->maxLength(100),
                    TextInput::make('amount')->label('Valor (R$)')->required()->placeholder('250,00'),
                    Textarea::make('reason')->label('Motivo')->required()->maxLength(300),
                ])
                ->action(function (array $data) {
                    $record = $this->getRecord();
                    [$cents, $problem] = Money::parseCents((string) $data['amount']);
                    $to = Contract::query()->where('tenant_id', $record->tenant_id)->where('code', trim((string) $data['to']))->first();
                    try {
                        if ($cents === null) {
                            throw new AccessRefused((string) $problem);
                        }
                        if ($to === null) {
                            throw new AccessRefused('Contrato de destino não encontrado neste credor.');
                        }
                        // Na demonstração, o texto livre do visitante não fica gravado.
                        $reason = DemoMode::enabled() ? 'motivo descartado na demonstração' : (string) $data['reason'];
                        app(CreditTransfer::class)->transfer(Auth::user(), Contract::findOrFail($data['from']), $to, $cents, $reason);
                    } catch (AccessRefused $e) {
                        Notification::make()->title($e->getMessage())->danger()->send();

                        return;
                    }
                    Notification::make()->title('Crédito transferido')->success()->send();
                    $this->getRecord()->refresh();
                }),
        ];
    }

    /** @return list<int> contratos em que o cliente tem título */
    private function contractIds(): array
    {
        return Bill::query()->where('customer_id', $this->getRecord()->id)->pluck('contract_id')->unique()->values()->all();
    }

    public function getTitle(): string
    {
        return $this->getRecord()->name;
    }
}
