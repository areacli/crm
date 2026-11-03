# Distribuição na SPA (14, R311, R317, R326; decisão 0025): filtros, as distribuições da página e, para os formulários, as operações credenciadas,
# as exposições e os motivos de recolher.
json.total @pagination.total
json.pagina @pagination.page
json.por_pagina @pagination.per_page
json.paginas @pagination.pages
json.varios_credores @several_tenants
json.filtros do
  json.operacoes(@operations.map { |operation| { id: operation.id.to_s, nome: operation.short_name } })
  json.situacoes(%w[in_force scheduled ended].map { |status| { id: status, nome: t("distributions.statuses.#{status}") } })
  json.origens(Distribution::SOURCES.map { |source| { id: source, nome: t("distributions.sources.#{source}") } })
  json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
end
accreditations = Accreditation.active.where(tenant_id: @tenants.map(&:id)).includes(:operation, :tenant).sort_by { |item| [ item.tenant.name, item.operation.short_name ] }
json.credenciadas(accreditations.map { |item| { id: item.id.to_s, nome: @several_tenants ? "#{item.operation.short_name} (#{item.tenant.name})" : item.operation.short_name } })
json.exposicoes(Distribution::EXPOSURES.map { |exposure| { id: exposure, nome: t("distributions.exposures.#{exposure}") } })
json.exposicao_padrao @tenants.first&.setting&.operation_default_exposure
json.motivos_de_recolher(Distribution::RECALL_REASONS.map { |reason| { id: reason, nome: t("distributions.end_reasons.#{reason}").capitalize } })
json.pode_distribuir policy(Distribution).new?
tons = { "in_force" => :success, "scheduled" => :info, "ended" => :neutral }
json.linhas @distributions do |distribution|
  json.id distribution.id
  json.alvo(distribution.customer ? distribution.customer.name : "Contrato #{distribution.contract.code}")
  json.rotulo distribution.target_label
  json.cliente_id distribution.customer_id
  json.operacao distribution.operation.short_name
  json.credor distribution.tenant.name
  json.exposicao_id distribution.exposure
  json.exposicao t("distributions.exposures.#{distribution.exposure}")
  json.inicio distribution.starts_on.iso8601
  json.fim distribution.ends_on&.iso8601
  json.agendada distribution.agendada?
  json.periodo "#{date_br(distribution.starts_on)} a #{distribution.ends_on ? date_br(distribution.ends_on) : "sem fim"}"
  json.origem t("distributions.sources.#{distribution.source}")
  json.situacao selo(t("distributions.statuses.#{distribution.status_key}"), tons.fetch(distribution.status_key))
  json.aberta distribution.ended_at.nil?
  json.detalhe(("Encerrada em #{datetime_br(distribution.ended_at)}: #{t("distributions.end_reasons.#{distribution.end_reason}", default: distribution.end_reason)}." if distribution.ended_at))
end
