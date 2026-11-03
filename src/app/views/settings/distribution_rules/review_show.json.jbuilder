# Conferência do impacto do enquadramento da distribuição na SPA (14, R343; decisão 0025): como fica, e quantos contratos entram e saem de cada operação.
json.credor_id @tenant.id.to_s
json.subtitulo "Enquadramento da distribuição de #{@tenant.name}. Nada muda até você confirmar."
json.como_fica(@proposal.items.map { |item| "#{@segments[item.segment_id]} → #{item.operation_ids.map { @operations[_1] }.join(", ")} (#{t("distributions.exposures.#{item.exposure}")})" } +
               [ "Equipe do credor (quem não atende nenhum item)" ])
json.conferindo @result.nil?
if @result
  json.linhas(@result["moves"].map do |name, move|
    { operacao: name, entram: number_br(move["in"]), saldo_entra: money(move["in_cents"]), saem: number_br(move["out"]), saldo_sai: money(move["out_cents"]) }
  end)
end
