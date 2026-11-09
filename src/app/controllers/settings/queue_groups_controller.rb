# Grupos (15, R353, R358): usuários do credor ligados a filas, em ordem; valem na hora, sem conferência, com o histórico (R357). Um grupo não
# mistura operações. Permissão 21, no credor do grupo.
module Settings
  class QueueGroupsController < ApplicationController
    before_action :set_tenant, only: %i[index new create]
    before_action :set_group, only: %i[edit update destroy]

    def index
      @groups = QueueGroup.where(tenant: @tenant).includes(:users, :work_queues).order(:name)
    end

    def new
      @group = QueueGroup.new(tenant: @tenant)
      load_choices
    end

    def create
      @group = QueueGroup.new(tenant: @tenant)
      save_group
    end

    def edit = load_choices

    def update = save_group

    def destroy
      @group.destroy!
      Change.record!(@group, "queue_group_deleted", tenant_id: @tenant.id, actor: Current.user, origin: "screen", before: @group.name)
      panel_finish(queues_queue_groups_path(credor: @tenant.id), notice: t(".done"), atualizar: true)
    end

    private
      def set_tenant
        tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_queues")).order(:name)
        @tenant = tenants.find_by(id: params[:credor]) || tenants.first or raise Pundit::NotAuthorizedError
        @tenants = tenants
        authorize WorkQueue.new(tenant: @tenant), :create?
      end

      def set_group
        @group = QueueGroup.where(tenant_id: Current.user.tenant_ids_with("manage_queues")).find(params[:id])
        @tenant = @group.tenant
        authorize WorkQueue.new(tenant: @tenant), :create?
      end

      # Quem pode estar num grupo: quem tem a 7 no credor. As filas: as que entregam, ativas.
      def load_choices
        ids = Membership.where(tenant: @tenant).select { |membership| membership.profile.permissions.include?("record_contact_attempts") }.map(&:user_id)
        @users = User.where(id: ids, active: true).order(:name)
        @queues = WorkQueue.where(tenant: @tenant, active: true, delivers: true).order(:subject, :position)
      end

      def save_group
        attributes = params.expect(group: [ :name, user_ids: [], queue_positions: {} ])
        before = @group.persisted? ? describe(@group) : nil
        positions = attributes[:queue_positions].to_h.filter_map { |id, position| [ id.to_i, position.to_i ] if position.present? }.sort_by(&:last)
        ApplicationRecord.transaction do
          @group.name = attributes[:name]
          @group.users = User.where(id: Array(attributes[:user_ids]).compact_blank)
          @group.save!
          @group.queue_group_queues.delete_all
          valid = WorkQueue.where(tenant: @tenant, id: positions.map(&:first)).pluck(:id)
          positions.each_with_index { |(id, _), index| QueueGroupQueue.create!(queue_group: @group, work_queue_id: id, position: index + 1) if valid.include?(id) }
          Change.record!(@group, before ? "queue_group_changed" : "queue_group_created", tenant_id: @tenant.id, actor: Current.user, origin: "screen", before: before, after: describe(@group.reload))
        end
        panel_finish(queues_queue_groups_path(credor: @tenant.id), notice: t("settings.queue_groups.saved"), atualizar: true)
      rescue ActiveRecord::RecordInvalid
        load_choices
        render(@group.persisted? ? :edit : :new, status: :unprocessable_content)
      end

      def describe(group) = "#{group.name}: #{group.users.map(&:name).sort.join(', ')} → #{group.work_queues.map(&:name).join(', ')}"
  end
end
