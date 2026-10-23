{{-- Tabela de colunas da planilha (R44): nome, se é obrigatória, formato e exemplo. --}}
<x-ui.card title="Colunas da planilha">
    <x-ui.table>
        <thead><tr><x-ui.th>Coluna</x-ui.th><x-ui.th>Obrigatória</x-ui.th><x-ui.th>Formato</x-ui.th><x-ui.th>Exemplo</x-ui.th></tr></thead>
        <tbody class="divide-y divide-slate-200">
            @foreach ($columns as $column)
                <tr>
                    <td class="px-2 py-1.5 font-mono">{{ $column['name'] }}</td>
                    <td class="px-2 py-1.5">{{ $column['required'] ? 'Sim' : 'Não' }}</td>
                    <td class="px-2 py-1.5">{{ $column['format'] }}</td>
                    <td class="px-2 py-1.5 font-mono">{{ $column['example'] }}</td>
                </tr>
            @endforeach
        </tbody>
    </x-ui.table>
    <p class="mt-2 text-sm text-slate-500">CSV com ponto e vírgula, UTF-8. A planilha-modelo enviada sem alteração passa na conferência.</p>
</x-ui.card>
