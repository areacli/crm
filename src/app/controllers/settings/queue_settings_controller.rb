# Ordem, trava e intervalos de uma fila (15, R350, R355, R356): valem na hora, sem conferência (não mudam quem está em qual fila), com o
# histórico (R357). A trilha padrão "sem fila" não tem o que ajustar. Permissão 21, no credor da fila.
module Settings
  class QueueSettingsController < ApplicationController
    FIELDS = %i[order_by order_tiebreak lock_minutes interval_no_contact_hours interval_third_party_hours interval_customer_hours].freeze

    before_action :set_queue

    def edit; end

    def update
      attributes = params.expect(queue: FIELDS)
      before = describe(@queue)
      @queue.assign_attributes(order_by: attributes[:order_by], order_tiebreak: attributes[:order_tiebreak].presence, lock_minutes: attributes[:lock_minutes],
                               interval_no_contact_minutes: minutes(attributes[:interval_no_contact_hours]),
                               interval_third_party_minutes: minutes(attributes[:interval_third_party_hours]),
                               interval_customer_minutes: minutes(attributes[:interval_customer_hours]))
      if @queue.save
        Change.record!(@queue, "queue_settings_changed", tenant_id: @queue.tenant_id, actor: Current.user, origin: "screen", before: before, after: describe(@queue))
        QueuesJob.perform_later(@queue.tenant)
        return panel_finish(queues_work_queues_path(credor: @queue.tenant_id), notice: t(".done"), atualizar: true) if spa?

        redirect_back_or_to queues_work_queues_path(credor: @queue.tenant_id), notice: t(".done"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    private
      def set_queue
        @queue = policy_scope(WorkQueue).find(params[:id])
        authorize @queue, :update?
      end

      def minutes(hours) = (BigDecimal(hours.to_s.tr(",", ".").presence || "0") * 60).round

      def describe(queue)
        "#{queue.name}: ordem #{queue.order_by}/#{queue.order_tiebreak || '-'}; trava #{queue.lock_minutes} min; intervalos #{queue.interval_no_contact_minutes}/" \
          "#{queue.interval_third_party_minutes}/#{queue.interval_customer_minutes} min"
      end
  end
end
