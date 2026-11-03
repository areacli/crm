# Enquadramento das filas na SPA (15, R349, R357; decisão 0025): por sujeito, os itens em ordem com a trilha padrão no fim; o índice de cada item é o
# que as ações (editar, mover, excluir) usam, como nas páginas do servidor.
json.credor_id @tenant.id.to_s
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.enquadramentos(@framings.map do |subject, framing|
  items = framing.reject(&:catch_all)
  { sujeito: subject, nome: t("queues.subjects.#{subject}"),
    itens: framing.map do |queue|
      index = items.index(queue)
      { id: queue.id, indice: index, ordem: queue.catch_all ? "—" : (index + 1).to_s, nome: queue.name, trilha_padrao: queue.catch_all, sem_fila: !queue.delivers,
        segmento: queue.segment&.name || "Quem não atende nenhum item", segmento_id: queue.segment_id,
        ordem_da_fila: queue.delivers ? [ t("queues.orders.#{queue.order_by}"), (t("queues.orders.#{queue.order_tiebreak}") if queue.order_tiebreak) ].compact.join("; empate, ") : "—",
        tempos: queue.delivers ? "#{queue.lock_minutes} min · #{duracao_curta(queue.interval_no_contact_minutes)} / #{duracao_curta(queue.interval_third_party_minutes)} / #{duracao_curta(queue.interval_customer_minutes)}" : "—",
        na_fila: queue.delivers ? number_br(@counts[queue.id].to_i) : "—",
        entrega: queue.delivers, primeiro: index.nil? || index.zero?, ultimo: index.nil? || index == items.size - 1 }
    end }
end)
