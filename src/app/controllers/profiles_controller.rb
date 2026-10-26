# Perfis dos credores em que a pessoa gerencia perfis (permissão 11): criar, alterar e apagar, com as 16 permissões (R30 a R35).
# As regras de dados (R35, R41, PD6, PD7, AC7) estão em `Access::ProfileManager`.
class ProfilesController < ApplicationController
  before_action :set_profile, only: %i[ edit update destroy ]

  def index
    authorize Profile
    @tenants = manageable_tenants.pluck(:name, :id)
    @several_tenants = @tenants.size > 1
    scope = policy_scope(Profile).includes(:tenant).order(:name, :id)
    scope = scope.where(tenant_id: params[:tenant]) if params[:tenant].present?
    @pagination = Pagination.new(scope, page: params[:page], per_page: params[:per_page])
    @profiles = @pagination.records
    @users_by_profile = Membership.where(profile_id: @profiles.map(&:id)).group(:profile_id).count
  end

  def new
    authorize Profile
    @tenants = manageable_tenants
    @profile = Profile.new(tenant: @tenants.find_by(id: params[:tenant_id]) || @tenants.first, permissions: %w[ view_portfolio ])
  end

  def create
    attributes = params.expect(profile: [ :tenant_id, :name, permissions: [] ])
    @tenants = manageable_tenants
    tenant = Tenant.find_by(id: attributes[:tenant_id]) or return head(:not_found)
    authorize Profile.new(tenant: tenant)
    @profile = manager.create(tenant: tenant, name: attributes[:name], permissions: attributes[:permissions])

    if @profile.persisted?
      panel_finish(profiles_path, notice: t(".done", name: @profile.name), atualizar: true)
    else
      render :new, status: :unprocessable_content
    end
  rescue Access::Refused => error
    @profile = Profile.new(tenant: tenant, name: attributes[:name], permissions: attributes[:permissions])
    @error = error.message
    render :new, status: :unprocessable_content
  end

  def edit
  end

  def update
    attributes = params.expect(profile: [ :name, permissions: [] ])
    manager.update(@profile, name: attributes[:name], permissions: attributes[:permissions])

    if @profile.errors.empty?
      panel_finish(profiles_path, notice: t(".done", name: @profile.name), atualizar: true)
    else
      render :edit, status: :unprocessable_content
    end
  rescue Access::Refused => error
    @error = error.message
    render :edit, status: :unprocessable_content
  end

  def destroy
    manager.destroy(@profile)
    panel_finish(profiles_path, notice: t(".done", name: @profile.name), atualizar: true)
  rescue Access::Refused => error
    panel_refuse(profiles_path, error.message)
  end

  private
    def set_profile
      @profile = Profile.includes(:tenant).find(params[:id])
      authorize @profile
    end

    def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with("manage_profiles")).order(:name)

    def manager = Access::ProfileManager.new(Current.user, request: request)
end
