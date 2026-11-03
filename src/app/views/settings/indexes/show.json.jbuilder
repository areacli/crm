# Índices do Banco Central na SPA (08, R145 a R147, R157, R158; decisão 0025): a situação da busca e as últimas buscas, e por credor os meses da página com
# as quatro séries (valor do Banco Central, parcial ou a correção do credor) e o detalhe de cada mês. Corrigir e desfazer: só nos credores com a permissão 14;
# "Buscar índices agora": quem tem a 14 em algum credor.
pode_buscar = Current.user.permitted_anywhere?("change_financial_policies")
ultima = @last_success && (@last_success.finished_at || @last_success.started_at)
falhou = @last_failure && (@last_success.nil? || @last_failure.started_at > @last_success.started_at)

json.pode_buscar pode_buscar
json.buscando @running
json.ultima_busca(ultima ? "Última busca com sucesso: #{datetime_br(ultima)}." : "Ainda não houve busca com sucesso.")
json.falha(falhou ? "Falha em #{datetime_br(@last_failure.started_at)}: #{@last_failure.note}#{" Há #{(Date.current - ultima.to_date).to_i} dias sem busca com sucesso." if ultima}" : nil)
json.buscas(@runs.map do |run|
  status = t("indexes.run_status.#{run.status}")
  { id: run.id, quando: datetime_br(run.started_at), resultado: run.note.present? ? "#{status} — #{run.note}" : status, meses: number_br(run.processed) }
end)
json.vazio @grid.empty?
json.pagina @grid.page
json.paginas @grid.pages
json.series(IndexRate::SERIES.map { |series| { id: series, nome: IndexRate.label(series) } })
json.credores(@tenants.map do |tenant|
  pode_corrigir = @can_correct.include?(tenant.id)
  { id: tenant.id, nome: tenant.name, pode_corrigir: pode_corrigir,
    meses: @grid.months.map do |month|
      cells = IndexRate::SERIES.map { |series| [ series, @grid.cell(tenant.id, series, month) ] }
      { mes: months_label(month), credor_id: tenant.id,
        # Uma célula por série, na ordem de `series`: o texto e se é correção do credor (o selo "Corrigido").
        valores: cells.map do |_series, cell|
          texto = if cell.adjustment
            index_percent(cell.adjustment.value)
          elsif cell.bank
            "#{index_percent(cell.bank)}#{" (parcial)" if cell.partial}"
          else
            "sem valor"
          end
          { texto: texto, corrigido: cell.adjustment.present? }
        end,
        detalhe: cells.filter_map do |series, cell|
          nome = IndexRate.label(series)
          if cell.adjustment
            adjustment = cell.adjustment
            { texto: "#{nome}: corrigido para #{index_percent(adjustment.value)}#{cell.bank ? " (Banco Central: #{index_percent(cell.bank)})" : " (incluído à mão)"} " \
                     "em #{datetime_br(adjustment.adjusted_at)}#{" por #{adjustment.user.name}" if adjustment.user}: #{adjustment.reason}",
              correcao_id: (adjustment.id if pode_corrigir), serie: nome }
          elsif cell.bank
            { texto: "#{nome}: Banco Central, buscado em #{date_br(cell.fetched_at.to_date)}#{", parcial" if cell.partial}.", correcao_id: nil, serie: nome }
          end
        end }
    end }
end)
