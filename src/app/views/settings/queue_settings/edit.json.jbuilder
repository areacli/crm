# Ordem e tempos de uma fila na SPA (15, R350, R355, R356): os valores atuais e os critérios.
json.nome @queue.name
json.ordens(WorkQueue::ORDERS.map { |order| { id: order, nome: t("queues.orders.#{order}") } })
json.ordem @queue.order_by
json.desempate @queue.order_tiebreak.to_s
json.trava @queue.lock_minutes
json.sem_contato (@queue.interval_no_contact_minutes / 60.0).round(1)
json.terceiro (@queue.interval_third_party_minutes / 60.0).round(1)
json.cliente (@queue.interval_customer_minutes / 60.0).round(1)
