# Uma fila na SPA (15, R357; decisão 0025): quem está nela, em ordem, com a situação e a entrega aberta.
queue = @queue
json.id queue.id
json.credor_id @tenant.id.to_s
json.nome queue.name
json.ordem "#{t("queues.subjects.#{queue.subject}")} em ordem: #{[ t("queues.orders.#{queue.order_by}"), (t("queues.orders.#{queue.order_tiebreak}") if queue.order_tiebreak) ].compact.join("; empate, ")}."
json.coluna_do_sujeito t("queues.subject_one.#{queue.subject}").capitalize
json.total @placements.total
json.pagina @placements.page
json.por_pagina @placements.per_page
json.paginas @placements.pages
json.linhas(@placements.records.map do |placement|
  delivery = @open[placement.subject_id]
  situacao = if delivery
    selo("Com #{delivery.user.name}", :info)
  elsif placement.available_at&.future?
    selo("Aguardando até #{l(placement.available_at, format: :short)}", :neutral)
  else
    selo("Disponível", :success)
  end
  { posicao: number_br(placement.rank), sujeito: @names[placement.subject_id] || "—", situacao: situacao, entrega_id: delivery&.id }
end)
