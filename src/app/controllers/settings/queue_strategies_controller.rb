# Estratégia de um operador entre as filas dele (15, R353): em ordem, pesos ou uma de cada vez. Quem tem a 21 num credor muda o modo e as
# posições e pesos das filas desse credor; as filas dos outros credores ficam como estão e aparecem só pela contagem (decisão 6 do plano
# técnico da camada 19). Vale na hora, com o histórico.
module Settings
  class QueueStrategiesController < ApplicationController
    before_action :set_user

    def edit; end

    def update
      attributes = params.expect(strategy: [ :mode, weights: {}, positions: {} ])
      before = describe
      mine = @mine.map(&:id)
      others = Array(@strategy.entries).reject { |entry| mine.include?(entry["queue_id"]) }
      ordered = mine.sort_by { |id| attributes[:positions].to_h[id.to_s].to_i }
      entries = ordered.map { |id| { "queue_id" => id, "weight" => attributes[:weights].to_h[id.to_s].to_i.clamp(1, 100) } }
      @strategy.assign_attributes(mode: attributes[:mode], entries: entries + others, cursor: {})
      if @strategy.save
        Change.record!(@strategy, "queue_strategy_changed", tenant_id: @tenant.id, actor: Current.user, origin: "screen", before: before, after: describe)
        redirect_to queues_queue_groups_path(tenant_id: @tenant.id), notice: t(".done"), status: :see_other
      else
        render :edit, status: :unprocessable_content
      end
    end

    private
      def set_user
        tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_queues"))
        @tenant = tenants.find_by(id: params[:tenant_id]) || tenants.first or raise Pundit::NotAuthorizedError
        authorize WorkQueue.new(tenant: @tenant), :create?
        @user = User.joins(:queue_group_users).merge(QueueGroupUser.where(queue_group_id: QueueGroup.where(tenant: @tenant).select(:id))).distinct.find(params[:id])
        @strategy = QueueStrategy.for(@user)
        all = Queues::Strategy.new(@user, @user.tenant_ids_with("record_contact_attempts")).queues
        @mine = all.select { |queue| queue.tenant_id == @tenant.id }
        @others_count = all.size - @mine.size
      end

      def describe = "#{@user.name}: #{@strategy.mode} #{Array(@strategy.entries).map { "#{_1['queue_id']}×#{_1['weight']}" }.join(', ')}"
  end
end
