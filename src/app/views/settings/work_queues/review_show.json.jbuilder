# Conferência do impacto do enquadramento das filas na SPA (15, R357; decisão 0025): como fica, e o que muda (nulo enquanto confere).
json.credor_id @tenant.id.to_s
json.subtitulo "Enquadramento das filas de #{t("queues.subjects.#{@proposal.subject}").downcase} de #{@tenant.name}. Nada muda até você confirmar."
json.como_fica(@proposal.items.map { |item| "#{item.name}#{" (sem fila)" unless item.delivers}" } + [ "#{t("queues.catch_all")} (quem não atende nenhum item)" ])
json.conferindo @result.nil?
if @result
  json.total number_br(@result["total"])
  json.linhas(@result["rows"].map { |row| { de: row["from"] || "—", para: row["to"], quantos: number_br(row["count"]) } })
end
