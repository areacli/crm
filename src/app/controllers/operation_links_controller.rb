# Vínculo dado pelo gestor da operação (14, R310): só nos credores cuja política deixa, com os perfis disponíveis para operações.
class OperationLinksController < ApplicationController
  before_action :set_member

  def new
    @accreditations = accreditations
  end

  def create
    attributes = params.expect(link: %i[accreditation_id profile_id])
    @accreditations = accreditations
    accreditation = @accreditations.find { |item| item.id == attributes[:accreditation_id].to_i } or return refuse(t("operations.refused.profile_not_available"))
    profile = accreditation.tenant.profiles.find_by(id: attributes[:profile_id], available_to_operations: true) or return refuse(t("operations.refused.profile_not_available"))
    Operations::Accreditor.new(Current.user).link(accreditation, user: @member.user, profile: profile)
    panel_finish(operation_people_path, notice: t(".done", name: @member.user.name, tenant: accreditation.tenant.name), navegar: true)
  rescue Operations::Accreditor::Refused, ActiveRecord::RecordInvalid => error
    refuse(error.respond_to?(:record) ? error.record.errors.full_messages.to_sentence : error.message)
  end

  private
    def set_member
      @member = policy_scope(OperationMember).includes(:user).find(params[:operation_person_id])
      authorize @member, :update?
    end

    def accreditations
      policy = OperationMemberPolicy.new(Current.user, @member)
      Accreditation.where(operation_id: @member.operation_id).active.includes(tenant: :profiles).select { |accreditation| policy.link?(accreditation) }
    end

    def refuse(message)
      @error = message
      render :new, status: :unprocessable_content
    end
end
