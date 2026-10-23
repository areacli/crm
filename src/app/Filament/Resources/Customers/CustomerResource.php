<?php

namespace App\Filament\Resources\Customers;

use App\Enums\Permission;
use App\Filament\Resources\Customers\Pages\ListCustomers;
use App\Filament\Resources\Customers\Pages\ViewCustomer;
use App\Filament\Resources\Customers\Schemas\CustomerInfolist;
use App\Filament\Resources\Customers\Tables\CustomersTable;
use App\Models\Customer;
use BackedEnum;
use Filament\Resources\Resource;
use Filament\Schemas\Schema;
use Filament\Support\Icons\Heroicon;
use Filament\Tables\Table;
use Illuminate\Database\Eloquent\Builder;
use Illuminate\Support\Facades\Auth;

/**
 * Clientes (lista e ficha). Neste incremento só leitura: criar, editar ou apagar cliente à mão está fora do
 * escopo (especificação 01); o cadastro chega pela carga da carteira.
 */
class CustomerResource extends Resource
{
    protected static ?string $model = Customer::class;

    protected static string|BackedEnum|null $navigationIcon = Heroicon::OutlinedUsers;

    protected static ?string $modelLabel = 'cliente';

    protected static ?string $pluralModelLabel = 'clientes';

    protected static ?string $slug = 'clientes';

    protected static ?int $navigationSort = 20;

    /** Só os clientes dos credores em que o usuário pode consultar a carteira (MT-5), mesmo por link direto; a policy cuida do resto. */
    public static function getEloquentQuery(): Builder
    {
        return Customer::query()->visibleTo(Auth::user(), Permission::ViewPortfolio);
    }

    public static function infolist(Schema $schema): Schema
    {
        return CustomerInfolist::configure($schema);
    }

    public static function table(Table $table): Table
    {
        return CustomersTable::configure($table);
    }

    public static function getPages(): array
    {
        return [
            'index' => ListCustomers::route('/'),
            'view' => ViewCustomer::route('/{record}'),
        ];
    }
}
