# Visão das filas na SPA (15, R357; decisão 0025): o credor (sem seleção global, MT-5), por fila os números e quem atende o quê agora.
json.credor_id @tenant.id.to_s
json.credores(@tenants.map { |tenant| { id: tenant.id.to_s, nome: tenant.name } })
json.filas @queues do |queue|
  json.id queue.id
  json.nome queue.name
  json.sem_grupo !@grouped.include?(queue.id)
  json.sujeito t("queues.subjects.#{queue.subject}")
  json.disponiveis number_br(@available[queue.id].to_i - @in_service[queue.id].to_i)
  json.em_atendimento number_br(@in_service[queue.id].to_i)
  json.aguardando number_br(@waiting[queue.id].to_i)
end
json.entregas @open do |delivery|
  json.id delivery.id
  json.operador delivery.user.name
  json.fila delivery.work_queue.name
  json.desde l(delivery.delivered_at, format: :short)
  json.travado_ate l(delivery.locked_until, format: :short)
end
