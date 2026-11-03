# O "Próximo" e o "Devolver" do operador (15, R353, R354), com a permissão 7 (registrar acionamentos). A entrega abre a ficha do cliente
# entregue, ou a do responsável financeiro do contrato entregue com o contrato como filtro da página.
class QueueDeliveriesController < ApplicationController
  rate_limit to: 60, within: 1.minute, only: :create

  def create
    raise Pundit::NotAuthorizedError unless Current.user.permitted_anywhere?("record_contact_attempts")

    skip_authorization
    result = Queues::NextDelivery.new(Current.user).call
    if result.delivery
      redirect_to self.class.ficha_path(self, result.delivery), status: :see_other
    else
      redirect_back_or_to root_path, alert: t("queues.next.#{result.reason}"), status: :see_other
    end
  end

  # Devolver: a entrega volta à fila (R354).
  def destroy
    skip_authorization
    delivery = QueueDelivery.open.find_by(user_id: Current.user.id)
    delivery&.finish!("returned")
    Queues::Broadcast.changed(delivery.tenant) if delivery
    redirect_back_or_to root_path, notice: t("queues.returned"), status: :see_other
  end

  # A ficha da entrega: o cliente, ou o contrato pela ficha do responsável financeiro (os titulares se não há; 04, R69c).
  def self.ficha_path(context, delivery)
    return context.customer_path(delivery.subject_id) if delivery.subject == "customers"

    links = ContractCustomer.where(contract_id: delivery.subject_id).to_a
    chosen = links.find { |link| Array(link.roles).include?("financial_responsible") } || links.first
    context.customer_path(chosen.customer_id, contrato: delivery.subject_id)
  end
end
