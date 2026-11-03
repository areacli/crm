# Formulário do aceite na SPA (11, R220; 14, R318): quem pode aceitar, os canais e o aviso das promessas de operação que o aceite cancela.
json.aviso(@undone.present? ? "Este aceite cancela #{@undone.map { |promise| "a promessa #{promise.number || 'pendente'} da #{promise.operation.short_name}" }.to_sentence}. A operação recebe um aviso." : nil)
json.canais(Agreement::CHANNELS.map { |channel| { id: channel, nome: channel_name(channel) } })
json.aceitantes(@acceptors.map { |customer, role| { id: customer.id.to_s, nome: "#{customer.name}, #{t("agreements.roles.#{role}")}" } })
