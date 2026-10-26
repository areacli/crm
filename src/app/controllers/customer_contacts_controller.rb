# Contatos do cliente editados na ficha (06, R113): criar e corrigir. A permissão 12 (e a 1) vale no credor do cliente (R113a); sem ela a recusa
# vira 404 registrada com o credor (R33). As regras de dados ficam em `Registry::ContactEditor`. Criar abre no painel lateral; corrigir telefone ou e-mail se faz
# na própria linha da tabela (sem formulário aberto), e o endereço, no painel; a resposta atualiza a ficha.
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

  # Corrigir: telefone e e-mail na própria linha (o htmx troca a linha pelos campos); endereço no painel.
  def edit
    authorize @customer, :edit_registry?
    @contact = @customer.contacts.find(params[:id])
    return render(partial: "customers/contacts/row", locals: { customer: @customer, contact: @contact, can_edit: true }) if row_request? && params[:cancelar]
    render(partial: "customers/contacts/row_editor", locals: { customer: @customer, contact: @contact, error: nil }) if row_request? && !@contact.address?
  end

  # Corrigir o contato: o antigo vira inválido e nasce o novo (R113).
  def update
    authorize @customer, :edit_registry?
    @contact = @customer.contacts.find(params[:id])
    editor.correct(@contact, params.expect(contact: [ :value, *Tenant::ADDRESS_FIELDS ]).to_h)
    panel_finish(customer_path(@customer, aba: "contatos"), notice: t(".done"), atualizar: true, via_htmx: panel_request? || row_request?)
  rescue Registry::Refused => error
    return redirect_to(customer_path(@customer, aba: "contatos"), alert: error.message, status: :see_other) unless panel_request? || row_request?
    return render(partial: "customers/contacts/row_editor", locals: { customer: @customer, contact: @contact, error: error.message }, status: :unprocessable_content) if row_request?

    @error = error.message
    render :edit, status: :unprocessable_content
  end

  private
    def set_customer = @customer = Customer.find(params[:customer_id])

    def editor = Registry::ContactEditor.new(Current.user)

    # A edição na linha é pedida pelo htmx com destino na própria linha (`contato-<id>`).
    def row_request? = request.headers["HX-Request"].present? && request.headers["HX-Target"].to_s.start_with?("contato-")
end
