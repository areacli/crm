# Guarda de dados na SPA (07, R138; decisão 0025): o prazo de cada credor, a anonimização prevista em 30 dias (com "reter"), os retidos (com "desfazer") e
# as últimas execuções da tarefa diária.
json.varios_credores @several_tenants
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.prazos(@settings.map do |setting|
  { credor_id: setting.tenant_id, texto: "#{setting.tenant.name}: #{setting.retention_years} #{setting.retention_years == 1 ? "ano" : "anos"} do fim da última relação em aberto.",
    pode_mudar: @can_change_period.include?(setting.tenant_id) }
end)
json.previstos do
  json.total @forecast.total
  json.pagina @forecast.page
  json.paginas @forecast.pages
  json.linhas(@forecast.records.map do |customer|
    { id: customer.id, credor: customer.tenant.name, cliente: customer.name, abre_ficha: @can_view_customer.include?(customer.tenant_id),
      fim: date_br(customer.attributes["ended_on"]), anonimizacao: date_br(customer.attributes["due_on"]) }
  end)
end
json.retidos do
  json.total @retained.total
  json.pagina @retained.page
  json.paginas @retained.pages
  json.linhas(@retained.records.map do |customer|
    { id: customer.id, credor: customer.tenant.name, cliente: customer.name, abre_ficha: @can_view_customer.include?(customer.tenant_id), motivo: customer.retained_reason,
      por: "#{customer.retained_by&.name || "—"} em #{date_br(customer.retained_at.to_date)}" }
  end)
end
json.execucoes(@runs.map do |run|
  { quando: datetime_br(run.started_at), credor: run.tenant&.name, resultado: "#{t("titular.run_status.#{run.status}")}#{" — #{run.note}" if run.note.present?}#{" (#{run.error_kind})" if run.error_kind.present?}",
    anonimizados: number_br(run.processed), falhas: number_br(run.failed) }
end)
