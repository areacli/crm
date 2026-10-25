module CustomerContacts
  # Situação de um contato (06, R113, R114): marcar inválido (com motivo), "não perturbe" (com a data do pedido) ou voltar a válido (com motivo).
  class StatusesController < ApplicationController
    def update
      customer = Customer.find(params[:customer_id])
      authorize customer, :edit_registry?
      contact = customer.contacts.find(params[:contact_id])
      attributes = params.expect(status: %i[status reason requested_on])
      editor = Registry::ContactEditor.new(Current.user)
      case attributes[:status]
      when "invalid" then editor.mark_invalid(contact, attributes[:reason])
      when "do_not_disturb" then editor.do_not_disturb(contact, attributes[:requested_on], attributes[:reason])
      when "valid" then editor.restore(contact, attributes[:reason])
      else raise Registry::Refused, t("registry.refused.status")
      end
      redirect_to customer_path(customer, anchor: "contatos"), notice: t(".done"), status: :see_other
    rescue Registry::Refused => error
      redirect_to customer_path(customer, anchor: "contatos"), alert: error.message, status: :see_other
    end
  end
end
