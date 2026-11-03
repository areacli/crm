# Resultado do lote na SPA (14, R316; decisão 0025): conferindo ou confirmando, a falha, ou o que vai (e o que foi) com o que fica de fora.
batch = @batch
summary = batch.summary
rodando = batch.checking? || (batch.checked? && summary["confirming"].present?)
json.id batch.id
json.titulo "Lote de distribuição à #{batch.operation.short_name}"
json.subtitulo "#{t("distribution_batches.kinds.#{batch.kind}")} · #{t("distributions.exposures.#{batch.exposure}")} · #{date_br(batch.starts_on)} a #{batch.ends_on ? date_br(batch.ends_on) : "sem fim"}"
json.rodando rodando
json.andamento(batch.checking? ? "Conferindo o lote…" : "Confirmando o lote…") if rodando
json.falha(batch.failed? ? summary["error"].presence || t("distribution_batches.failed") : nil)
json.confirmado batch.confirmed?
json.pode_confirmar batch.checked? && !rodando
unless rodando || batch.failed?
  linhas = [ "Vão #{number_br(summary["contracts"].to_i)} contratos (#{number_br(summary["targets"].to_i)} #{batch.target == "customer" ? "clientes" : "contratos"}), #{money(summary["balance_cents"].to_i)} em cobrança." ]
  linhas << "A distribuição por cliente leva #{number_br(summary["extra_contracts"])} contratos em que o cliente é só responsável financeiro." if summary["extra_contracts"].to_i.positive?
  linhas << "#{number_br(summary["refused_contracts"])} contratos ficam de fora: já estão com outra operação (exclusividade)." if summary["refused_contracts"].to_i.positive?
  linhas += Array(summary["refused"]).map { |row| "Contrato #{row["contract"]}: com a #{row["operation"]}" }
  linhas << "#{number_br(summary["missing_count"])} linhas da planilha não foram encontradas: #{Array(summary["missing"]).join(", ")}." if summary["missing_count"].to_i.positive?
  if batch.confirmed?
    linhas << "#{number_br(summary["created"].to_i)} distribuições criadas#{", #{summary["refused_at_confirm"]} recusadas na confirmação" if summary["refused_at_confirm"].to_i.positive?}."
  end
  json.resumo linhas
end
