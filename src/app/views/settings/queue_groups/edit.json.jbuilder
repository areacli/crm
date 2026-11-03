# Formulário do grupo na SPA (15, R353): o nome, os usuários que podem estar nele (com a 7 no credor) e as filas com a posição de cada uma no grupo.
positions = @group.queue_group_queues.to_h { [ _1.work_queue_id, _1.position ] }
json.nome @group.name.to_s
json.usuarios(@users.map { |user| { id: user.id.to_s, nome: user.name } })
json.selecionados(@group.users.map { |user| user.id.to_s })
json.filas(@queues.map { |queue| { id: queue.id.to_s, nome: "#{queue.name} (#{t("queues.subjects.#{queue.subject}").downcase})", posicao: positions[queue.id] } })
