# Resultado do "Conferir" na SPA (13, R288, revisão 3; decisão 0025). `estado`: vazio (ainda não conferiu), invalido, tempo (passou do tempo), contando
# (com o `id` para buscar o resultado de novo quando o tempo real avisar) ou pronto, com o total, o saldo e cada condição sozinha.
# Locais: probe, subject, expression (a árvore conferida).
noun = ->(n) { n == 1 ? segment_t("subjects.#{subject}.one") : segment_t("subjects.#{subject}.other") }
if probe.nil?
  json.estado "vazio"
  json.texto "\"Conferir\" mostra quantos #{segment_t("subjects.#{subject}.other")} o segmento pega hoje, sem gravar nada."
elsif probe["invalid"]
  json.estado "invalido"
  json.texto "Corrija os erros do texto para conferir."
elsif probe["timeout"]
  json.estado "tempo"
  json.texto "A contagem passou do tempo. O segmento é pesado: simplifique as condições ou use-o só no enquadramento."
elsif probe["status"] == "running"
  json.estado "contando"
  json.id probe["id"]
  json.texto "Contando…"
else
  total = probe["total"].to_i
  json.estado "pronto"
  json.texto "Pega #{number_br(probe["total"])} #{noun.call(total)} (#{money(probe["balance_cents"])} de saldo em cobrança)."
  json.zera total.zero?
  json.aviso("O segmento não pega ninguém hoje. Veja abaixo qual condição zera a contagem.") if total.zero?
  json.coluna segment_t("subjects.#{subject}.short").upcase_first
  conditions = []
  if expression && probe["conditions"].to_h.size > 1
    text = Segments::Text.new(expression)
    expression.each_condition do |node, address|
      count = probe["conditions"].to_h[address].to_i
      conditions << { condicao: text.short(node), quantos: "#{number_br(count)}#{" (zera)" if count.zero?}", zera: count.zero? }
    end
  end
  json.condicoes conditions
end
