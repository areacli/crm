# Usuários dos credores em que a pessoa gerencia usuários (permissão 10): uma linha por vínculo (R36). Criar com senha temporária,
# ligar quem já existe em outro credor (R36a) e a ficha com o histórico (R42). As ações sobre um vínculo estão em `Memberships::*`.
class MembershipsController < ApplicationController
  def index
    authorize Membership
    @tenants = manageable_tenants.pluck(:name, :id)
    @several_tenants = @tenants.size > 1
    scope = policy_scope(Membership).joins(:user).includes(:user, :tenant, :profile).order("users.name", :id)
    scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
    if params[:q].present?
      term = "%#{Membership.sanitize_sql_like(params[:q].strip)}%"
      scope = scope.where("users.name ILIKE :term OR users.email_address ILIKE :term", term: term)
    end
    @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
    @memberships = @pagination.records
    render partial: "memberships/result" if htmx_fragment?
  end

  def show
    @membership = Membership.includes(:user, :tenant, :profile).find(params[:id])
    authorize @membership
    @profiles = @membership.tenant.profiles.order(:name)
    @events = AccessEvent.where(user_id: @membership.user_id).where("tenant_id = ? OR tenant_id IS NULL", @membership.tenant_id)
      .includes(:actor).order(occurred_at: :desc, id: :desc).limit(100)
    response.headers["Cache-Control"] = "no-store" if flash[:temporary_password]
  end

  def new
    authorize Membership
    @tenants = manageable_tenants
    @tenant = @tenants.find_by(id: params[:tenant_id]) || @tenants.first
    @profiles = @tenant.profiles.order(:name)
    render partial: "memberships/profile_field" if htmx_fragment? && !panel_request?
  end

  def create
    attributes = params.expect(membership: %i[ tenant_id email_address name profile_id ])
    @tenants = manageable_tenants
    @tenant = Tenant.find_by(id: attributes[:tenant_id]) or return head(:not_found)
    authorize Membership.new(tenant: @tenant)
    @profiles = @tenant.profiles.order(:name)
    profile = @profiles.find_by(id: attributes[:profile_id])
    email_address = attributes[:email_address].to_s.strip.downcase
    return refuse(t(".profile_required")) unless profile

    existing = User.find_by(email_address: email_address)
    if existing
      manager.link(tenant: @tenant, user: existing, profile: profile)
      panel_finish(memberships_path, notice: t(".linked", name: existing.name, email: existing.email_address, tenant: @tenant.name), atualizar: true)
    else
      return refuse(t(".name_required")) if attributes[:name].blank?

      user, password = manager.create(tenant: @tenant, email_address: email_address, name: attributes[:name], profile: profile)
      flash[:temporary_password] = { "email" => user.email_address, "password" => password }
      panel_finish(memberships_path, atualizar: true)
    end
  rescue ActiveRecord::RecordInvalid => error
    refuse(error.record.errors.full_messages.to_sentence)
  rescue Access::Refused => error
    refuse(error.message)
  end

  # Alterar o nome (R36, revisão 3): é da pessoa, então só de quem não atua em outro credor (R36a). O nome se pede num modal pequeno.
  def edit
    @membership = Membership.includes(:user, :tenant).find(params[:id])
    authorize @membership, :edit_personal?
  end

  def update
    @membership = Membership.includes(:user, :tenant).find(params[:id])
    authorize @membership, :edit_personal?
    manager.rename(@membership, params.expect(user: [ :name ])[:name])
    panel_finish(membership_path(@membership), notice: t(".done"), atualizar: true)
  rescue ActiveRecord::RecordInvalid => error
    panel_error(error.record.errors.full_messages.to_sentence, membership_path(@membership), :edit)
  end

  private
    def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_users")).order(:name)

    def manager = Access::UserManager.new(Current.user, request: request)

    def refuse(message)
      @error = message
      @form = params.fetch(:membership, {}).permit(:email_address, :name, :profile_id)
      render :new, status: :unprocessable_content
    end
end
