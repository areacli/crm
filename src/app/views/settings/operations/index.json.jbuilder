# Operações credenciadas na SPA (14, R306, R307, R319, R325; decisão 0025): a lista, os credores para credenciar e as políticas das operações de cada credor.
tons = { "active" => :success, "suspended" => :warning, "ended" => :neutral }
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.linhas @accreditations do |accreditation|
  json.id accreditation.id
  json.operacao accreditation.operation.short_name
  json.cnpj Document.format(accreditation.operation.cnpj)
  json.credor accreditation.tenant.name
  json.situacao selo(t("operations.statuses.#{accreditation.status}"), tons.fetch(accreditation.status))
  json.pessoas @linked[[ accreditation.tenant_id, accreditation.operation_id ]].to_i
end
json.exposicoes(Distribution::EXPOSURES.map { |exposure| { id: exposure, nome: t("distributions.exposures.#{exposure}") } })
json.politicas(@tenants.map do |tenant|
  setting = tenant.setting
  { credor_id: tenant.id, credor: tenant.name, exclusiva: setting.operation_exclusive ? "0" : "1", exposicao: setting.operation_default_exposure,
    dias_uteis: setting.operation_exposure_business_days, ve_outros_acordos: setting.operation_sees_other_deals ? "1" : "0",
    outros_acionamentos: setting.operation_other_contact_attempts == "summary" ? "0" : "1", gestor_da_vinculos: setting.operation_manager_links ? "1" : "0" }
end)
