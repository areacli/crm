# Arquivo de acordos na SPA (11, R244; decisão 0025): o aviso do que vence sem estar em arquivo baixado, as exportações e os credores para exportar.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.pendencias(@unseen.map { |item| { titulo: item.bill.number, acordo_id: item.agreement.id, credor: item.tenant.name, vencimento: date_br(item.bill.due_date) } })
json.exportacoes @exports do |export|
  json.quando datetime_br(export.created_at)
  json.credor export.tenant.name
  json.forma t("agreements.export_forms.#{export.form}")
  json.linhas number_br(export.lines)
  json.quem(export.user&.name || "Sistema")
  json.endereco(export.available? ? agreement_export_path(export) : nil)
end
