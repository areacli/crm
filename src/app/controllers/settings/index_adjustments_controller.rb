module Settings
  # Correção de um índice pelo credor e o desfazimento dela (R145, R146): permissão 14 no credor, motivo obrigatório. A correção (4 campos) abre no painel lateral e o
  # desfazimento (motivo) num modal pequeno, os dois por `new`.
  class IndexAdjustmentsController < ApplicationController
    def new
      if params[:desfazer].present?
        @adjustment = IndexAdjustment.includes(:tenant).find(params[:desfazer])
        authorize @adjustment, :destroy?, policy_class: IndexAdjustmentPolicy
      else
        @tenant = Tenant.find(params[:tenant_id])
        authorize IndexAdjustment.new(tenant: @tenant), :create?, policy_class: IndexAdjustmentPolicy
      end
    end

    def create
      @tenant = Tenant.find(params[:tenant_id])
      authorize IndexAdjustment.new(tenant: @tenant), :create?, policy_class: IndexAdjustmentPolicy
      data = params.expect(adjustment: %i[series month value reason])
      Indexes::Adjuster.new(Current.user, @tenant).correct(series: data[:series], month: data[:month], value: data[:value], reason: data[:reason])
      panel_finish(settings_indexes_path, notice: t("indexes.adjust.done", tenant: @tenant.name), atualizar: true)
    rescue Indexes::Adjuster::Refused, ActiveRecord::RecordInvalid => error
      panel_error(error.message, settings_indexes_path)
    end

    def destroy
      @adjustment = IndexAdjustment.includes(:tenant).find(params[:id])
      authorize @adjustment, :destroy?, policy_class: IndexAdjustmentPolicy
      Indexes::Adjuster.new(Current.user, @adjustment.tenant).undo(series: @adjustment.series, month: @adjustment.month, reason: params.dig(:adjustment, :reason))
      panel_finish(settings_indexes_path, notice: t("indexes.adjust.undone", tenant: @adjustment.tenant.name), atualizar: true)
    rescue Indexes::Adjuster::Refused => error
      @tenant = @adjustment.tenant
      panel_error(error.message, settings_indexes_path)
    end
  end
end
