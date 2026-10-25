module Payments
  # Cópia dos dados do pagador no momento da emissão (12, R276a-8): nome, documento, endereço e, para o cartão, e-mail e telefone válidos do
  # cadastro do cliente. Compartilhada pelo instrumento e pelo link de checkout; a cópia sai na anonimização do cliente e entra na exportação.
  module Payer
    module_function

    def snapshot(customer)
      address = best_address(customer)
      { payer_name: customer.name, payer_document: customer.document.to_s.first(14),
        payer_address: address ? address.slice(:street, :number, :complement, :district, :city, :state, :zip).transform_keys(&:to_s).compact_blank : {} }
    end

    # Com e-mail e telefone (para o cartão, que os pede ao fornecedor).
    def snapshot_with_contacts(customer)
      snapshot(customer).merge(payer_email: best_contact(customer, "email")&.value.to_s.first(254).presence, payer_phone: best_contact(customer, "phone")&.key.to_s.first(20).presence)
    end

    def best_address(customer)
      customer.contacts.select { |contact| contact.address? && contact.status_valid? && contact.zip.present? }.min_by(&:id)
    end

    def best_contact(customer, kind)
      customer.contacts.select { |contact| contact.kind == kind && contact.status_valid? }.min_by(&:id)
    end
  end
end
