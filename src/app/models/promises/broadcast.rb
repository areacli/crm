module Promises
  # Evento de invalidação das promessas (decisão 0020, sem polling): quem tem a ficha de um cliente ou a lista de pendentes aberta busca o trecho de novo.
  module Broadcast
    module_function

    def changed(tenant, customer_ids = [])
      message = { event: "promises-changed" }
      PromisesChannel.broadcast_to(tenant, message)
      Customer.where(id: customer_ids).find_each { |customer| PromisesChannel.broadcast_to(customer, message) } if customer_ids.any?
    end
  end
end
