module Agreements
  # Evento de invalidação dos acordos (decisão 0020, sem polling): quem tem a ficha de um cliente, a lista de acordos ou a de pendentes aberta busca o trecho de novo.
  module Broadcast
    module_function

    def changed(tenant, customer_ids = [])
      message = { event: "agreements-changed" }
      AgreementsChannel.broadcast_to(tenant, message)
      Customer.where(id: customer_ids).find_each { |customer| AgreementsChannel.broadcast_to(customer, message) } if customer_ids.any?
    end
  end
end
