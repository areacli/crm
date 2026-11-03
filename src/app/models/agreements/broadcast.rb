module Agreements
  # Evento de invalidação dos acordos (decisão 0020, sem polling): quem tem a ficha de um cliente, a lista de acordos ou a de pendentes aberta busca o trecho de novo.
  module Broadcast
    module_function

    # Lote (decisão 0021): dentro do bloco, a gravação de cada registro não avisa sozinha; quem processa o lote avisa uma vez no fim (`changed`).
    def quiet
      previous = ActiveSupport::IsolatedExecutionState[:agreements_broadcast_quiet]
      ActiveSupport::IsolatedExecutionState[:agreements_broadcast_quiet] = true
      yield
    ensure
      ActiveSupport::IsolatedExecutionState[:agreements_broadcast_quiet] = previous
    end

    def quiet? = ActiveSupport::IsolatedExecutionState[:agreements_broadcast_quiet] == true

    def changed(tenant, customer_ids = [])
      message = { event: "agreements-changed" }
      AgreementsChannel.broadcast_to(tenant, message)
      Customer.where(id: customer_ids).find_each { |customer| AgreementsChannel.broadcast_to(customer, message) } if customer_ids.any?
    end
  end
end
