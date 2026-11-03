module Promises
  # Evento de invalidação das promessas (decisão 0020, sem polling): quem tem a ficha de um cliente ou a lista de pendentes aberta busca o trecho de novo.
  module Broadcast
    module_function

    # Lote (decisão 0021): dentro do bloco, a gravação de cada registro não avisa sozinha; quem processa o lote avisa uma vez no fim (`changed`).
    def quiet
      previous = ActiveSupport::IsolatedExecutionState[:promises_broadcast_quiet]
      ActiveSupport::IsolatedExecutionState[:promises_broadcast_quiet] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:promises_broadcast_quiet] = previous
    end

    def quiet? = ActiveSupport::IsolatedExecutionState[:promises_broadcast_quiet] == true

    def changed(tenant, customer_ids = [])
      message = { event: "promises-changed" }
      PromisesChannel.broadcast_to(tenant, message)
      Customer.where(id: customer_ids).find_each { |customer| PromisesChannel.broadcast_to(customer, message) } if customer_ids.any?
    end
  end
end
