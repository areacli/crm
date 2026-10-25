# Contatos do cliente editados na ficha (06, R113): criar e corrigir. A permissão 12 (e a 1) vale no credor do cliente (R113a); sem ela a recusa
# vira 404 registrada com o credor (R33). As regras de dados ficam em `Registry::ContactEditor`; a resposta volta para a ficha, no bloco de contatos.
class CustomerContactsController < ApplicationController
  before_action :set_customer

  def create
    authorize @customer, :edit_registry?
    attributes = params.expect(contact: [ :kind, :value, *Tenant::ADDRESS_FIELDS ])
    contact = editor.add(@customer, kind: attributes[:kind], fields: attributes.to_h)
    # R126 (DC5): o contato igual ao do credor entra inválido, e a tela avisa.
    back_to_customer(notice: contact.status_invalid? ? t(".done_tenant_contact") : t(".done"))
  rescue Registry::Refused => error
    back_to_customer(alert: error.message)
  end

  # Corrigir o contato: o antigo vira inválido e nasce o novo (R113).
  def update
    authorize @customer, :edit_registry?
    contact = @customer.contacts.find(params[:id])
    editor.correct(contact, params.expect(contact: [ :value, *Tenant::ADDRESS_FIELDS ]).to_h)
    back_to_customer(notice: t(".done"))
  rescue Registry::Refused => error
    back_to_customer(alert: error.message)
  end

  private
    def set_customer = @customer = Customer.find(params[:customer_id])

    def editor = Registry::ContactEditor.new(Current.user)

    def back_to_customer(**flash) = redirect_to(customer_path(@customer, anchor: "contatos"), status: :see_other, **flash)
end
