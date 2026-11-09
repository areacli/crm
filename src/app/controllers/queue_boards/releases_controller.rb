# Liberar a entrega de um operador (15, R354, R357): quem gerencia a fila (permissão 21) no credor da entrega.
module QueueBoards
  class ReleasesController < ApplicationController
    def create
      delivery = QueueDelivery.open.find(params[:id])
      authorize delivery.work_queue, :update?
      delivery.finish!("released", by: Current.user)
      Change.record!(delivery, "queue_delivery_released", tenant_id: delivery.tenant_id, actor: Current.user, origin: "screen", before: delivery.user.name)
      Queues::Broadcast.changed(delivery.tenant)
      return panel_finish(queues_board_path(credor: delivery.tenant_id), notice: t("queues.released"), atualizar: true) if spa?

      redirect_back_or_to queues_board_path(credor: delivery.tenant_id), notice: t("queues.released"), status: :see_other
    end
  end
end
