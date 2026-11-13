# Lote de distribuição (14, R316): os clientes do filtro da lista, um segmento ou uma planilha (coluna `documento` ou `contrato`); conferência e
# confirmação em segundo plano, com o resultado avisado pelo WebSocket (sem polling).
class DistributionBatchesController < ApplicationController
  FILTERS = %w[busca faixa segmento credor promessa endereco].freeze

  before_action :set_batch, only: %i[show confirm discard]

  def new
    authorize Distribution
    @accreditations = accreditations
    @segments = Segment.where(tenant_id: @accreditations.map(&:tenant_id), active: true).order(:subject, :name_key)
    @selection = params.permit(FILTERS).to_h
  end

  def create
    @accreditations = accreditations
    attributes = params.expect(distribution_batch: [ :accreditation_id, :kind, :segment_id, :file, :exposure, :starts_on, :ends_on, selection: FILTERS ])
    accreditation = @accreditations.find { |item| item.id == attributes[:accreditation_id].to_i } or return refuse(t("distributions.refused.operation_required"))
    authorize Distribution.new(tenant: accreditation.tenant), :create?
    batch = build(accreditation, attributes)
    batch.save!
    DistributionBatchJob.perform_later(batch, "check")
    # Na SPA (decisão 0028), o lote abre na aba dele, onde a conferência chega pelo tempo real.
    return panel_finish(distribution_batch_path(batch), notice: t("distribution_batches.checking"), navegar: true) if spa?

    redirect_to distribution_batch_path(batch), status: :see_other
  rescue Distributions::Refused, ActiveRecord::RecordInvalid, CSV::MalformedCSVError => error
    refuse(error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message)
  end

  def show
    @cable = [ { channel: "DistributionsChannel", tenant_id: @batch.tenant_id } ].to_json
    render partial: "distribution_batches/result", locals: { batch: @batch } if fragment?
  end

  def confirm
    if @batch.expired? || !@batch.checked?
      return panel_finish(distribution_batch_path(@batch), notice: t("distribution_batches.expired"), tom: :danger, atualizar: true) if spa?

      return redirect_to(distribution_batch_path(@batch), alert: t("distribution_batches.expired"), status: :see_other)
    end

    @batch.update!(summary: @batch.summary.merge("confirming" => true))
    DistributionBatchJob.perform_later(@batch, "confirm")
    return panel_finish(distribution_batch_path(@batch), notice: t("distribution_batches.confirming"), atualizar: true) if spa?

    redirect_to distribution_batch_path(@batch), status: :see_other
  end

  def discard
    @batch.update!(status: "discarded") if @batch.checked? || @batch.failed?
    panel_finish(distributions_path, notice: t("distribution_batches.discarded"), atualizar: true)
  end

  private
    def set_batch
      @batch = DistributionBatch.visible_to(Current.user, "distribute_portfolio").includes(:operation, :segment, :tenant).find(params[:id])
      authorize Distribution.new(tenant: @batch.tenant), :create?
    end

    def accreditations
      tenant_ids = Current.user.tenant_ids_with("distribute_portfolio")
      Accreditation.active.where(tenant_id: tenant_ids).includes(:operation, :tenant).sort_by { |item| [ item.tenant.name, item.operation.short_name ] }
    end

    def build(accreditation, attributes)
      batch = DistributionBatch.new(tenant: accreditation.tenant, operation: accreditation.operation, user: Current.user, kind: attributes[:kind],
                                    exposure: attributes[:exposure].presence || accreditation.tenant.setting.operation_default_exposure,
                                    starts_on: attributes[:starts_on].present? ? Date.iso8601(attributes[:starts_on]) : Date.current,
                                    ends_on: attributes[:ends_on].present? ? Date.iso8601(attributes[:ends_on]) : nil)
      case attributes[:kind]
      when "segment"
        batch.segment = Segment.find_by(tenant: accreditation.tenant, id: attributes[:segment_id], active: true) or raise Distributions::Refused, t("distribution_batches.segment_required")
        batch.target = batch.segment.subject == "customers" ? "customer" : "contract"
      when "file"
        batch.target, values = read_file(attributes[:file])
        batch.summary = { "values" => values }
      when "selection"
        filters = attributes[:selection].to_h.symbolize_keys
        query = Portfolio::Query.new(Current.user).customers(search: filters[:busca], bracket: filters[:faixa], segment: filters[:segmento], tenant_id: accreditation.tenant_id,
                                                              promise: FilterValue.from_url(filters[:promessa]), address: FilterValue.from_url(filters[:endereco]))
        batch.target = "customer"
        batch.summary = { "values" => query.reorder(nil).pluck("customers.id").uniq }
      else
        raise Distributions::Refused, t("distribution_batches.kind_required")
      end
      batch
    end

    # Planilha CSV com a coluna `documento` (clientes) ou `contrato` (contratos, pelo código). Com `contrato`, a coluna `sistema` é opcional (17, R421): diz de
    # qual sistema é o contrato quando o código existe em mais de um, e cada linha vira o par `[código, sistema]`.
    def read_file(upload)
      raise Distributions::Refused, t("distribution_batches.file_required") unless upload.respond_to?(:read)

      rows = CSV.parse(upload.read.force_encoding("UTF-8").delete_prefix("﻿"), headers: true, col_sep: ";")
      headers = rows.headers.map { |header| header.to_s.strip.downcase }
      raise Distributions::Refused, t("distribution_batches.file_columns") unless [ %w[documento], %w[contrato], %w[contrato sistema] ].include?(headers.compact_blank.sort)

      return [ "customer", rows.map { |row| row[0].to_s.strip }.compact_blank.uniq ] if headers.include?("documento")
      return [ "contract", rows.map { |row| row[headers.index("contrato")].to_s.strip }.compact_blank.uniq ] unless headers.include?("sistema")

      pairs = rows.map { |row| [ row[headers.index("contrato")].to_s.strip, row[headers.index("sistema")].to_s.squish ] }
      [ "contract", pairs.reject { |code, _system| code.empty? }.uniq ]
    end

    def refuse(message)
      @error = message
      @accreditations ||= accreditations
      @segments = Segment.where(tenant_id: @accreditations.map(&:tenant_id), active: true).order(:subject, :name_key)
      @selection = params.dig(:distribution_batch, :selection)&.permit(FILTERS)&.to_h || {}
      render :new, status: :unprocessable_content
    end
end
