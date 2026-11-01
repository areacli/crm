# Pessoas da operação (14, R310, R310a, R327): o gestor da operação cadastra e desativa as pessoas dela, uma vez para todos os credores, e vê
# os vínculos de cada uma por credor. Dar vínculo, só nos credores que deixam (R319).
class OperationPeopleController < ApplicationController
  def index
    authorize OperationMember
    @operation = Current.user.operation
    @members = policy_scope(OperationMember).includes(:user).order(manager: :desc, active: :desc).sort_by { |member| [ member.active? ? 0 : 1, member.user.name ] }
    @memberships = Membership.where(user_id: @members.map(&:user_id), operation_id: @operation.id).active.includes(:tenant, :profile).group_by(&:user_id)
    @linkable = linkable_accreditations
  end

  def new
    authorize OperationMember
  end

  def create
    authorize OperationMember
    attributes = params.expect(operation_member: %i[name email_address manager])
    user, password = Operations::People.new(Current.user).create_person(Current.user.operation, name: attributes[:name], email_address: attributes[:email_address], manager: attributes[:manager] == "1")
    flash[:temporary_password] = { "email" => user.email_address, "password" => password } if password
    panel_finish(operation_people_path, notice: t(".done", name: user.name), navegar: true)
  rescue ActiveRecord::RecordInvalid => error
    @error = error.record.errors.full_messages.to_sentence
    render :new, status: :unprocessable_content
  rescue Operations::Accreditor::Refused => error
    @error = error.message
    render :new, status: :unprocessable_content
  end

  # Ativar, desativar e marcar como gestor (pelo menu da linha, com confirmação).
  def update
    member = policy_scope(OperationMember).find(params[:id])
    authorize member
    people = Operations::People.new(Current.user)
    case params[:change]
    when "activate" then people.set_active(member, true)
    when "deactivate" then people.set_active(member, false)
    when "manager" then people.set_manager(member, true)
    when "not_manager" then people.set_manager(member, false)
    else return head(:unprocessable_content)
    end
    panel_finish(operation_people_path, notice: t(".done", name: member.user.name), navegar: true)
  rescue Operations::Accreditor::Refused => error
    panel_finish(operation_people_path, notice: error.message, tom: :danger, navegar: true)
  end

  private
    def linkable_accreditations
      Accreditation.where(operation: Current.user.operation).active.includes(:tenant).select { |accreditation| OperationMemberPolicy.new(Current.user, OperationMember.new(operation: Current.user.operation)).link?(accreditation) }
    end
end
