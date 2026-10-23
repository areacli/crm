<x-filament::section heading="Colunas da planilha" :compact="true" :collapsible="false">
    <div class="overflow-x-auto">
        <table class="w-full text-left text-sm">
            <thead>
                <tr class="border-b border-gray-200 dark:border-white/10">
                    <th class="py-1 pe-3">Coluna</th>
                    <th class="py-1 pe-3">Obrigatória</th>
                    <th class="py-1 pe-3">Formato</th>
                    <th class="py-1">Exemplo</th>
                </tr>
            </thead>
            <tbody>
                @foreach ($columns as $column)
                    <tr class="border-b border-gray-100 dark:border-white/5">
                        <td class="py-1 pe-3 font-mono">{{ $column['name'] }}</td>
                        <td class="py-1 pe-3">{{ $column['required'] ? 'Sim' : 'Não' }}</td>
                        <td class="py-1 pe-3">{{ $column['format'] }}</td>
                        <td class="py-1 font-mono">{{ $column['example'] }}</td>
                    </tr>
                @endforeach
            </tbody>
        </table>
    </div>
    <p class="mt-2 text-sm text-gray-500">CSV com ponto e vírgula, UTF-8. A planilha-modelo enviada sem alteração passa na conferência.</p>
</x-filament::section>
