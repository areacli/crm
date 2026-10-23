<?php

namespace App\Livewire\Concerns;

use Illuminate\Contracts\Pagination\LengthAwarePaginator;
use Illuminate\Database\Eloquent\Builder;
use Livewire\Attributes\Url;
use Livewire\WithPagination;

/**
 * Tabela de lista do CRM (P22): busca, ordenação, 20 registros por página com 20, 50 e 100 à escolha. O componente define
 * a consulta (já com o escopo por credor das políticas) e as colunas ordenáveis; o trait cuida do resto.
 */
trait WithTable
{
    use WithPagination;

    public const array PER_PAGE_OPTIONS = [20, 50, 100];

    #[Url(as: 'q')]
    public string $search = '';

    #[Url(as: 'ordem')]
    public string $sort = '';

    #[Url(as: 'sentido')]
    public string $dir = 'desc';

    #[Url(as: 'por_pagina')]
    public int $perPage = 20;

    public function updatedSearch(): void
    {
        $this->resetPage();
    }

    public function updatedPerPage(): void
    {
        if (! in_array($this->perPage, self::PER_PAGE_OPTIONS, true)) {
            $this->perPage = 20;
        }
        $this->resetPage();
    }

    /** Clicar na coluna ordena por ela; clicar de novo inverte o sentido. */
    public function sortBy(string $field): void
    {
        if (! in_array($field, $this->sortable(), true)) {
            return;
        }
        $this->dir = $this->sort === $field && $this->dir === 'asc' ? 'desc' : 'asc';
        $this->sort = $field;
        $this->resetPage();
    }

    /** @return list<string> colunas que o usuário pode ordenar */
    protected function sortable(): array
    {
        return [];
    }

    /** @param  Builder<*>  $query */
    protected function paginateTable(Builder $query): LengthAwarePaginator
    {
        if ($this->sort !== '' && in_array($this->sort, $this->sortable(), true)) {
            $query->reorder($this->sort, $this->dir === 'asc' ? 'asc' : 'desc');
        }
        $perPage = in_array($this->perPage, self::PER_PAGE_OPTIONS, true) ? $this->perPage : 20;

        return $query->paginate($perPage);
    }
}
