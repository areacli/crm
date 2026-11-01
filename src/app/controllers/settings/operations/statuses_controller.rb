# Suspender, encerrar e reativar o credenciamento (14, R307), com motivo, no painel.
module Settings
  module Operations
    class StatusesController < ApplicationController
      before_action :set_accreditation

      def new
        @status = params[:status].presence_in(Accreditation.statuses.keys) or return head(:not_found)
      end

      def create
        @status = params.expect(accreditation: %i[status reason])[:status].presence_in(Accreditation.statuses.keys) or return head(:not_found)
        ::Operations::Accreditor.new(Current.user).change_status(@accreditation, @status, params[:accreditation][:reason])
        panel_finish(settings_operation_path(@accreditation),
                     notice: t("operations.status_done.#{@status}", name: @accreditation.operation.short_name, tenant: @accreditation.tenant.name), atualizar: true)
      rescue ::Operations::Accreditor::Refused => error
        @error = error.message
        render :new, status: :unprocessable_content
      end

      private
        def set_accreditation
          @accreditation = policy_scope(Accreditation).includes(:operation, :tenant).find(params[:operation_id])
          authorize @accreditation, :update?
        end
    end
  end
end
