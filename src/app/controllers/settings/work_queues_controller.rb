# Enquadramentos da fila (15, R349, R357): de clientes e de contratos, os itens em ordem, cada um uma fila ou "sem fila", com a trilha padrão
# no fim. Incluir, mudar, mover e tirar montam uma proposta, que passa pela conferência do impacto em segundo plano antes de valer. Permissão 21.
module Settings
  class WorkQueuesController < ApplicationController
    before_action :set_tenant

    def index
      @framings = WorkQueue::SUBJECTS.index_with { |subject| WorkQueue.framing(@tenant, subject) }
      @counts = QueuePlacement.where(tenant: @tenant).where.not(work_queue_id: nil).group(:work_queue_id).count
      @cable = [ { channel: "QueuesChannel", tenant_id: @tenant.id } ].to_json
    end

    def new
      @subject = subject_param
      load_choices
    end

    def create
      @subject = subject_param
      attributes = params.expect(queue: %i[segment_id name delivers position])
      review(Queues::Proposal.current(@tenant, @subject).with_included(attributes[:segment_id], attributes[:name], attributes[:delivers] == "1", attributes[:position]))
    rescue Queues::Refused => error
      load_choices
      @error = error.message
      render :new, status: :unprocessable_content
    end

    def edit
      @subject = subject_param
      @index = params[:id].to_i
      @item = Queues::Proposal.current(@tenant, @subject).items.fetch(@index)
      load_choices
    end

    def update
      @subject = subject_param
      attributes = params.expect(queue: %i[segment_id name delivers])
      review(Queues::Proposal.current(@tenant, @subject).with_changed(params[:id].to_i, attributes[:segment_id], attributes[:name], attributes[:delivers] == "1"))
    rescue Queues::Refused, IndexError => error
      panel_finish(queues_work_queues_path(credor: @tenant.id), notice: error.message, tom: :danger, navegar: true, mesma_aba: true)
    end

    def move = review(Queues::Proposal.current(@tenant, subject_param).with_moved(params[:id].to_i, params[:deslocamento].to_i))
    def destroy = review(Queues::Proposal.current(@tenant, subject_param).with_removed(params[:id].to_i))

    def review_show
      @token = params[:token].to_s
      @proposal = Queues::Proposal.from_token(@tenant, @token)
      @result = Queues::Review.read(@token)
      @cable = [ { channel: "QueuesChannel", tenant_id: @tenant.id } ].to_json
      render partial: "settings/work_queues/review", locals: { result: @result } if fragment?
    rescue Queues::Refused => error
      redirect_to queues_work_queues_path(credor: @tenant.id), alert: error.message, status: :see_other
    end

    def confirm
      Queues::Applier.new(Current.user).confirm(@tenant, params[:token].to_s)
      panel_finish(queues_work_queues_path(credor: @tenant.id), notice: t(".done"), navegar: true, mesma_aba: true)
    rescue Queues::Refused => error
      panel_finish(queues_work_queues_path(credor: @tenant.id), notice: error.message, tom: :danger, navegar: true, mesma_aba: true)
    end

    private
      def set_tenant
        tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_queues")).order(:name)
        @tenant = tenants.find_by(id: params[:credor]) || tenants.first or raise Pundit::NotAuthorizedError
        @tenants = tenants
        authorize WorkQueue.new(tenant: @tenant), :create?
      end

      def subject_param = WorkQueue::SUBJECTS.include?(params[:sujeito]) ? params[:sujeito] : "contracts"

      def load_choices
        @current = Queues::Proposal.current(@tenant, @subject).items
        used = @current.map(&:segment_id) - [ @item&.segment_id ]
        @segments = Segment.where(tenant: @tenant, subject: @subject, active: true).where.not(id: used).order(:name_key)
      end

      def review(proposal)
        token = proposal.token
        QueuesJob.perform_later(@tenant, token: token)
        url = review_queues_work_queues_path(credor: @tenant.id, token: token)
        # Na SPA, a conferência toma o lugar do enquadramento na mesma aba; o "Confirmar" e o "Descartar" voltam a ele.
        panel_finish(url, navegar: true, mesma_aba: true)
      end
  end
end
