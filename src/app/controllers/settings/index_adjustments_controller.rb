module Settings
  # Correção de um índice pelo credor e o desfazimento dela (R145, R146): permissão 14 no credor, motivo obrigatório.
  class IndexAdjustmentsController < ApplicationController
    def create
      tenant = Tenant.find(params[:tenant_id])
      authorize IndexAdjustment.new(tenant: tenant), :create?, policy_class: IndexAdjustmentPolicy
      data = params.expect(adjustment: %i[series month value reason])
      Indexes::Adjuster.new(Current.user, tenant).correct(series: data[:series], month: data[:month], value: data[:value], reason: data[:reason])
      redirect_to settings_indexes_path, notice: t("indexes.adjust.done", tenant: tenant.name), status: :see_other
    rescue Indexes::Adjuster::Refused, ActiveRecord::RecordInvalid => error
      redirect_to settings_indexes_path, alert: error.message, status: :see_other
    end

    def destroy
      adjustment = IndexAdjustment.includes(:tenant).find(params[:id])
      authorize adjustment, :destroy?, policy_class: IndexAdjustmentPolicy
      Indexes::Adjuster.new(Current.user, adjustment.tenant).undo(series: adjustment.series, month: adjustment.month, reason: params.dig(:adjustment, :reason))
      redirect_to settings_indexes_path, notice: t("indexes.adjust.undone", tenant: adjustment.tenant.name), status: :see_other
    rescue Indexes::Adjuster::Refused => error
      redirect_to settings_indexes_path, alert: error.message, status: :see_other
    end
  end
end
