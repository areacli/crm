# Conferência do impacto do enquadramento financeiro na SPA (13, R272, R291; decisão 0025), na ordem da R291: o que muda numa frase; o que foi alterado
# (antes e depois, curto e por extenso); por item; de onde para onde; valor atualizado; avisos. Enquanto confere, só a frase e as alterações.
review = @review
running = review["status"] == "running"
failed = review["status"] == "failed"
done = !running && !failed
total = review["total"].to_i
summary = if running
  "Conferindo… O resultado aparece aqui sozinho, em segundos na maior parte das vezes. Nada muda até você confirmar."
elsif failed
  ""
elsif total.zero?
  "Nenhum contrato muda de item. Nada muda até você confirmar."
else
  "Esta mudança move #{number_br(total)} #{total == 1 ? 'contrato' : 'contratos'}, com #{money(review['balance_cents'])} de saldo. Nada muda até você confirmar."
end

json.id @id
json.credor_id @tenant.id.to_s
json.subtitulo "Enquadramento financeiro de #{@tenant.name}"
json.conferindo running
json.falhou failed
json.pronto done
json.erro(failed ? review["error"].to_s : "")
json.token review["token"]
json.voltar review["back"]
json.resumo summary
json.alteracoes(Array(review["changes"]).map do |change|
  { o_que: change["what"], antes: change.dig("before", "short"), antes_extenso: change.dig("before", "long"),
    depois: change.dig("after", "short"), depois_extenso: change.dig("after", "long") }
end)

if done
  json.itens(Array(review["items"]).map do |item|
    { nome: item["name"], entram: number_br(item["in"]), saldo_entra: money(item["in_cents"]), saem: number_br(item["out"]), saldo_sai: money(item["out_cents"]) }
  end)
  json.movimentos(Array(review["moves"]).map do |move|
    { de: move["from"], para: move["to"], contratos: number_br(move["contracts"]), saldo: money(move["balance_cents"]) }
  end)
  json.tem_valores !review["values"].nil?
  json.valores(Array(review["values"]).map do |row|
    { nome: row["name"], clientes: number_br(row["customers"]), antes: money(row["before"]), depois: money(row["after"]), diferenca: money(row["after"].to_i - row["before"].to_i) }
  end)
  warnings = Array(review["cdc"]).map { |name| "Multa acima de 2% em #{name}: em relação de consumo com crédito ou financiamento, o limite é 2% (CDC, art. 52, § 1º). Confirme se os contratos deste item estão fora dessa regra." }
  warnings << "Entre os contratos que mudam, #{number_br(review['mixed'])} são mistos (responsáveis PF e PJ)." if review["mixed"].to_i.positive?
  json.avisos warnings
else
  json.itens []
  json.movimentos []
  json.tem_valores false
  json.valores []
  json.avisos []
end
