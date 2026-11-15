# Tarefas das filas (21, R446; 15, revisão 3): nome, instrução e prazo em dias, no lugar do dono. A tarefa usada numa régua
# não se apaga, só se desativa, e a lista mostra em quais réguas ela é usada. Permissão 21.
module Settings
  class QueueTasksController < ApplicationController
    before_action :set_tenant
    before_action :set_task, only: %i[edit update]

    def index
      @tasks = QueueTask.where(tenant: @tenant).order(:name).to_a
    end

    def new
      @task = QueueTask.new(tenant: @tenant, due_days: 3, active: true)
    end

    def create
      @task = QueueTask.new(task_params.merge(tenant: @tenant))
      @task.save!
      Change.record!(@task, "created", tenant_id: @tenant.id, actor: Current.user, field: "name", after: @task.name)
      panel_finish(queues_queue_tasks_path(credor: @tenant.id), notice: t(".done", name: @task.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid
      render :new, status: :unprocessable_content
    end

    def edit
    end

    def update
      before = @task.attributes.slice("name", "instruction", "due_days", "active")
      @task.update!(task_params)
      before.each { |field, value| Change.record!(@task, "updated", tenant_id: @tenant.id, actor: Current.user, field: field, before: value.to_s, after: @task[field].to_s) if @task[field] != value }
      panel_finish(queues_queue_tasks_path(credor: @tenant.id), notice: t(".done", name: @task.name), atualizar: true)
    rescue ActiveRecord::RecordInvalid
      render :edit, status: :unprocessable_content
    end

    private
      def set_tenant
        @tenants = Tenant.where(id: Current.user.tenant_ids_with(QueueTaskPolicy::KEY)).order(:name)
        @tenant = @tenants.find_by(id: params[:credor]) || @tenants.first or raise Pundit::NotAuthorizedError
        authorize QueueTask.new(tenant: @tenant), :create?
      end

      def set_task = @task = QueueTask.find_by!(id: params[:id], tenant_id: @tenant.id)

      def task_params
        attributes = params.expect(queue_task: %i[name instruction due_days active])
        attributes[:active] = attributes[:active] == "1" if attributes.key?(:active)
        attributes
      end
  end
end
