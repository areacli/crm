# Contatos do cliente editados na ficha (06, R113): criar e corrigir. A permissão 12 (e a 1) vale no credor do cliente (R113a); sem ela a recusa
# vira 404 registrada com o credor (R33). As regras de dados ficam em `Registry::ContactEditor`. Criar abre num diálogo; telefone e e-mail se corrigem na célula, e o
# endereço no detalhe da linha; a resposta atualiza a ficha.
class CustomerContactsController < ApplicationController
  before_action :set_customer

  def new
    authorize @customer, :edit_registry?
  end

  def create
    authorize @customer, :edit_registry?
    attributes = params.expect(contact: [ :kind, :value, *Tenant::ADDRESS_FIELDS ])
    contact = editor.add(@customer, kind: attributes[:kind], fields: attributes.to_h)
    # R126 (DC5): o contato igual ao do credor entra inválido, e a tela avisa.
    panel_finish(customer_path(@customer, aba: "contatos"), notice: contact.status_invalid? ? t(".done_tenant_contact") : t(".done"), atualizar: true)
  rescue Registry::Refused => error
    return redirect_to(customer_path(@customer, aba: "contatos"), alert: error.message, status: :see_other) unless panel_request?

    @error = error.message
    render :new, status: :unprocessable_content
  end

  # Corrigir o endereço: o formulário abre no detalhe da linha (telefone e e-mail se corrigem na célula, pelo `update` com `X-CRM-Inline`).
  def edit
    authorize @customer, :edit_registry?
    @contact = @customer.contacts.find(params[:id])
  end

  # Corrigir o contato: o antigo vira inválido e nasce o novo (R113).
  def update
    authorize @customer, :edit_registry?
    @contact = @customer.contacts.find(params[:id])
    corrected = editor.correct(@contact, params.expect(contact: [ :value, *Tenant::ADDRESS_FIELDS ]).to_h)
    # Na SPA, telefone e e-mail se corrigem na célula (design system, 7.1): o antigo fica inválido e nasce outro contato, então a aba se refaz.
    return inline_finish(corrected.try(:value) || @contact.value, atualizar: true, aviso: t(".done")) if inline?

    panel_finish(customer_path(@customer, aba: "contatos"), notice: t(".done"), atualizar: true)
  rescue Registry::Refused => error
    return inline_refuse(error.message) if inline?
    return redirect_to(customer_path(@customer, aba: "contatos"), alert: error.message, status: :see_other) unless panel_request?

    @error = error.message
    render :edit, status: :unprocessable_content
  end

  private
    def set_customer = @customer = Customer.find(params[:customer_id])

    def editor = Registry::ContactEditor.new(Current.user)
end
