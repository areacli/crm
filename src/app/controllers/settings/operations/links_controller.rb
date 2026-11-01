# Vínculos das pessoas da operação neste credor (14, R310): a permissão 18 ou a 10 do credor, com os perfis disponíveis para operações.
module Settings
  module Operations
    class LinksController < ApplicationController
      before_action :set_accreditation

      def new
        @member = @accreditation.operation.members.active.includes(:user).find(params[:member_id])
        @profiles = @accreditation.tenant.profiles.where(available_to_operations: true).order(:name)
      end

      def create
        attributes = params.expect(link: %i[member_id profile_id])
        @member = @accreditation.operation.members.active.includes(:user).find(attributes[:member_id])
        @profiles = @accreditation.tenant.profiles.where(available_to_operations: true).order(:name)
        profile = @profiles.find_by(id: attributes[:profile_id])
        return refuse(t("operations.refused.profile_not_available")) unless profile

        ::Operations::Accreditor.new(Current.user).link(@accreditation, user: @member.user, profile: profile)
        panel_finish(settings_operation_path(@accreditation), notice: t(".done", name: @member.user.name, profile: profile.name), atualizar: true)
      rescue ::Operations::Accreditor::Refused, ActiveRecord::RecordInvalid => error
        refuse(error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message)
      end

      def destroy
        membership = Membership.find_by!(id: params[:id], tenant_id: @accreditation.tenant_id, operation_id: @accreditation.operation_id)
        ::Operations::Accreditor.new(Current.user).unlink(membership)
        panel_finish(settings_operation_path(@accreditation), notice: t(".done", name: membership.user.name), atualizar: true)
      end

      private
        def set_accreditation
          @accreditation = Accreditation.includes(:operation, :tenant).find(params[:operation_id])
          authorize @accreditation, :link?
        end

        def refuse(message)
          @error = message
          render :new, status: :unprocessable_content
        end
    end
  end
end
