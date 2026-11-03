# Estratégia de um operador na SPA (15, R353): o modo e, para as filas deste credor, a posição e o peso.
entries = Array(@strategy.entries).index_by { _1["queue_id"] }
json.nome @user.name
json.credor @tenant.name
json.modos(QueueStrategy::MODES.map { |mode| { id: mode, nome: t("queues.modes.#{mode}") } })
json.modo @strategy.mode
json.filas(@mine.each_with_index.map { |queue, index| { id: queue.id.to_s, nome: queue.name, posicao: (entries.keys.index(queue.id) || index) + 1, peso: entries.dig(queue.id, "weight") || 1 } })
json.outras(@others_count.positive? ? "Além destas, #{@user.name} está em #{@others_count} #{@others_count == 1 ? "fila" : "filas"} de outros credores, que ficam como estão." : nil)
