# Lista de clientes na SPA (R21; decisão 0025): as linhas da página, a paginação (P22), as opções dos filtros e o que a pessoa pode fazer.
# Os valores vêm formatados pelos mesmos auxiliares das páginas do servidor (moeda, documento, faixa), e os centavos para ordenar.
recordable = Current.user.tenant_ids_with("record_contact_attempts")

json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.segmento_lento @query.segment_too_slow?
json.segmento(@segment ? { id: @segment.id, nome: @segment.name, resumo: @segment.text.lines.drop(1).map(&:short).join(" · ") } : nil)
json.filtros do
  json.credores(@tenants.map { |nome, id| { id: id.to_s, nome: nome } })
  json.faixas(@brackets.map { |rotulo, valor| { id: valor.to_s, nome: rotulo } })
  json.segmentos(@segments.flat_map { |grupo, opcoes| opcoes.map { |nome, id| { id: id.to_s, nome: nome, grupo: grupo } } })
  json.cidade Current.user.permitted_anywhere?("edit_customer_registry")
end
json.pode do
  json.distribuir Current.user.permitted_anywhere?("distribute_portfolio")
end
json.linhas @customers do |customer|
  json.id customer.id
  json.nome customer.name
  json.documento customer.masked_document
  json.credor customer.tenant.name
  json.titulos number_br(customer.bills_count)
  json.vencido money(customer.overdue_cents)
  json.atualizado(@updated_totals.key?(customer.id) ? money(@updated_totals[customer.id]) : "—")
  json.a_vencer(customer.tenant_id && @settings.fetch(customer.tenant_id).upcoming_display == "detail_only" ? "—" : money(customer.upcoming_cents))
  json.faixa(customer.bills_count.to_i.zero? ? "sem títulos em cobrança" : @query.bracket_label(customer.tenant_id, customer.max_days_overdue))
  json.enquadramento(@tier_names[customer.id] || t("tiers.none"))
  json.pode do
    json.registrar_acionamento recordable.include?(customer.tenant_id) && !customer.anonymized?
  end
end
