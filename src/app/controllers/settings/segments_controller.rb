module Settings
  # Segmentos do credor (13, R252 a R264, R273, R288 a R290, R295, R301 a R305): lista, editor de texto na linguagem com "Como fica" ao vivo e
  # "Conferir", criar, editar, apagar o segmento sem uso. Mudar as condições de um segmento usado no enquadramento leva à conferência do impacto
  # (R272). Sem JavaScript, "Conferir" e "Salvar" enviam o texto e a página volta com a leitura e os erros.
  class SegmentsController < ApplicationController
    include TierReview

    FIELDS = %i[name source].freeze

    before_action :set_segment, only: %i[show edit update destroy]

    def index
      authorize Segment
      @tenant_ids = policy_scope(Segment).distinct.pluck(:tenant_id) | policy_scope(Tier).distinct.pluck(:tenant_id)
      @tenants = Tenant.where(id: @tenant_ids).order(:name).to_a
      @filters = params.permit(:busca, :seleciona, :uso, :situacao).to_h.symbolize_keys
      @segments = filtered(policy_scope(Segment).includes(:tiers)).ordered.group_by(&:tenant_id)
      @can_change = Current.user.tenant_ids_with("change_financial_policies")
      @result_names = ContactResult.where(tenant_id: @tenant_ids).pluck(:id, :name).to_h
    end

    def show; end

    # Segmento novo: em branco, a partir de um exemplo pronto (R290) ou cópia de outro ("Duplicar").
    def new
      @tenant = tenant_for_segments(params[:tenant_id])
      source = params[:from].present? ? Segment.find_by(id: params[:from], tenant_id: @tenant.id) : nil
      example = ::Segments::Examples.find(params[:exemplo])
      subject = source&.subject || example&.subject || params[:subject].presence_in(Segment::SUBJECTS) || "contracts"
      @segment = Segment.new(tenant: @tenant, subject: subject, name: source ? "#{source.name} (cópia)" : example&.name.to_s)
      tree = source&.expression || example&.tree
      @source = tree ? ::Segments::Text.new(::Segments::Expression.new(tree.merge("subject" => subject))).short_text : "#{I18n.t("segment_language.subjects.#{subject}.short")}\n  "
      @parsed = parser.parse(@source) if tree
    end

    def create
      @tenant = tenant_for_segments(params[:tenant_id])
      @segment = Segment.new(tenant: @tenant)
      read_form
      return render_editor(:new) if editing?
      return render_editor(:new, status: :unprocessable_content) unless @parsed.ok?

      if @segment.save
        log("created", nil, @segment.text.short_text)
        redirect_to settings_segments_path, notice: t("segments.flash.created", name: @segment.name), status: :see_other
      else
        render_editor(:new, status: :unprocessable_content)
      end
    end

    def edit
      @source = @segment.text.short_text
      @parsed = parser.parse(@source)
    end

    def update
      before = @segment.text.short_text
      read_form
      return render_editor(:edit) if editing?
      return render_editor(:edit, status: :unprocessable_content) unless @parsed.ok? && @segment.valid?
      # R272: segmento usado no enquadramento muda só depois da conferência do impacto.
      return render_review(::Tiers::Proposal.current(@tenant).with_segment(@segment), back: edit_settings_segment_path(@segment)) if @segment.used?

      @segment.save!
      log("updated", before, @segment.text.short_text) if before != @segment.text.short_text
      redirect_to settings_segments_path, notice: t("segments.flash.updated", name: @segment.name), status: :see_other
    end

    # Apagar, só o segmento sem uso (R273).
    def destroy
      authorize @segment, :destroy?
      @segment.destroy!
      log("destroyed", @segment.text.short_text, nil)
      redirect_to settings_segments_path, notice: t("segments.flash.destroyed", name: @segment.name), status: :see_other
    end

    # Rascunho (htmx, enquanto o gestor escreve): só a coluna "Como fica", com a leitura e os erros de cada linha; a caixa de texto não é refeita.
    def draft
      @segment = params[:id].present? ? Segment.find(params[:id]).tap { |segment| authorize segment, :update? } : Segment.new(tenant: tenant_for_segments(params[:tenant_id]))
      @tenant = @segment.tenant
      read_form
      render partial: "settings/segments/como_fica", locals: { segment: @segment, source: @source, parsed: @parsed, probe: nil }
    end

    # "Conferir" (R288, revisão 3): em segundo plano; devolve o trecho "Contando…", que se completa quando o WebSocket avisa.
    def probe
      @segment = params[:id].present? ? Segment.find(params[:id]).tap { |segment| authorize segment, :update? } : Segment.new(tenant: tenant_for_segments(params[:tenant_id]))
      @tenant = @segment.tenant
      read_form
      probe = @parsed.ok? ? { "status" => "running", "id" => ::Segments::ProbeRun.start(@tenant, @segment.expression_object) } : { "invalid" => true }
      render partial: "settings/segments/probe", locals: { probe: probe, subject: @segment.subject, expression: @segment.expression_object }
    end

    def probe_result
      data = ::Segments::ProbeRun.fetch(params[:probe_id]) or return head(:not_found)
      @tenant = Tenant.find(data["tenant_id"])
      authorize Segment.new(tenant: @tenant), :create?
      expression = ::Segments::Expression.new(data["tree"])
      render partial: "settings/segments/probe", locals: { probe: data.merge("id" => params[:probe_id]), subject: expression.subject, expression: expression }
    end

    private
      def set_segment
        @segment = Segment.includes(:tenant).find(params[:id])
        authorize @segment
        @tenant = @segment.tenant
      end

      def tenant_for_segments(id)
        tenant = Tenant.find(id)
        authorize Segment.new(tenant: tenant), :create?
        tenant
      end

      def parser = ::Segments::Parser.new(@segment.tenant, subject: @segment.persisted? ? @segment.subject : nil)

      # O texto escrito vira a árvore (R301); com erro, o segmento fica inválido e a página mostra os erros por linha (R303).
      def read_form
        raw = params.fetch(:segment, {}).then { |value| value.respond_to?(:permit) ? value.permit(*FIELDS).to_h : {} }
        @segment.name = raw["name"] if raw.key?("name")
        @source = raw["source"].to_s
        @parsed = parser.parse(@source)
        return unless @parsed.ok?

        @segment.subject = @parsed.tree["subject"] unless @segment.persisted?
        @segment.expression = @parsed.tree
      end

      def editing? = params[:acao] == "conferir"

      def render_editor(template, status: :ok)
        @show_errors = status != :ok
        # Na SPA (decisão 0025), a recusa responde só a mensagem (o JSON de 422): os erros de cada linha a tela pede pelo rascunho.
        @error = "O texto tem erros; corrija o que está marcado em \"Como fica\" para salvar." if @show_errors && @parsed && !@parsed.ok?
        @probe = sync_probe if params[:acao] == "conferir"
        render template, status: status
      end

      # Sem JavaScript não há aviso pelo WebSocket: o "Conferir" do formulário comum calcula na própria requisição.
      def sync_probe
        return { "invalid" => true } unless @parsed.ok?

        { "status" => "done" }.merge(::Segments::Probe.new(@tenant, @segment.expression_object).call.deep_stringify_keys)
      end

      def filtered(scope)
        scope = scope.where("name_key like ?", "%#{FoldedText.fold(@filters[:busca])}%") if @filters[:busca].present?
        scope = scope.where(subject: @filters[:seleciona]) if @filters[:seleciona].in?(Segment::SUBJECTS)
        scope = scope.where(active: @filters[:situacao] == "ativos") if @filters[:situacao].in?(%w[ativos inativos])
        used = Tier.where(active: true).where.not(segment_id: nil).select(:segment_id)
        scope = @filters[:uso] == "em_uso" ? scope.where(id: used) : scope.where.not(id: used) if @filters[:uso].in?(%w[em_uso sem_uso])
        scope
      end

      def log(event, before, after)
        Change.record!(tenant_id: @segment.tenant_id, user: Current.user, subject_type: "segment", subject_id: @segment.id, event: event, field: "expression",
                       before: before, after: after, origin: "screen")
      end
  end
end
