module CustomerContacts
  # Situação de um contato (06, R113, R114): marcar inválido (com motivo), "não perturbe" (com a data do pedido) ou voltar a válido (com motivo). Cada uma
  # abre num modal pequeno (um ou dois campos); a ação do menu da linha escolhe a situação pelo parâmetro `status`.
  class StatusesController < ApplicationController
    before_action :set_contact

    def edit
      authorize @customer, :edit_registry?
      @status = params[:status].presence_in(%w[invalid do_not_disturb valid]) || "invalid"
    end

    def update
      authorize @customer, :edit_registry?
      attributes = params.expect(status: %i[status reason requested_on])
      @status = attributes[:status]
      editor = Registry::ContactEditor.new(Current.user)
      case attributes[:status]
      when "invalid" then editor.mark_invalid(@contact, attributes[:reason])
      when "do_not_disturb" then editor.do_not_disturb(@contact, attributes[:requested_on], attributes[:reason])
      when "valid" then editor.restore(@contact, attributes[:reason])
      else raise Registry::Refused, t("registry.refused.status")
      end
      panel_finish(customer_path(@customer, aba: "contatos"), notice: t(".done"), atualizar: true)
    rescue Registry::Refused => error
      return redirect_to(customer_path(@customer, aba: "contatos"), alert: error.message, status: :see_other) unless panel_request?

      @error = error.message
      @status = attributes&.dig(:status) || "invalid"
      render :edit, status: :unprocessable_content
    end

    private
      def set_contact
        @customer = Customer.find(params[:customer_id])
        @contact = @customer.contacts.find(params[:contact_id])
      end
  end
end
