# Sistemas do credor (17, R396 a R399): lista, cadastro, edição e exclusão, e na mesma página a política "Cadastro entre sistemas" (R410) dos
# credores com mais de um sistema além do CRM. A permissão 23 vale no credor do sistema (R427); quem a tem em mais de um credor vê os de todos,
# com a coluna Credor.
class SourceSystemsController < ApplicationController
  before_action :set_system, only: %i[edit update destroy]

  def index
    authorize SourceSystem
    load_page
    render partial: "source_systems/result" if fragment?
  end

  def new
    authorize SourceSystem
    @tenants = manageable_tenants
    @system = SourceSystem.new(key_kind: "own_id", tenant_id: params[:credor].presence)
  end

  def create
    @tenants = manageable_tenants
    attributes = params.expect(source_system: %i[tenant_id name key_kind])
    tenant = @tenants.find_by(id: attributes[:tenant_id]) or return head(:not_found)
    authorize SourceSystem.new(tenant: tenant)
    @system = manager.create(tenant: tenant, name: attributes[:name], key_kind: attributes[:key_kind])
    panel_finish(source_systems_path, notice: t(".done", name: @system.name), atualizar: true)
  rescue ActiveRecord::RecordInvalid => error
    @system = error.record
    render :new, status: :unprocessable_content
  end

  def edit
  end

  def update
    attributes = params.expect(source_system: %i[name key_kind])
    manager.update(@system, name: attributes[:name], key_kind: attributes[:key_kind].presence || @system.key_kind)
    panel_finish(source_systems_path, notice: t(".done", name: @system.name), atualizar: true)
  rescue ActiveRecord::RecordInvalid => error
    @system = error.record
    render :edit, status: :unprocessable_content
  end

  def destroy
    manager.destroy(@system)
    panel_finish(source_systems_path, notice: t(".done", name: @system.name), atualizar: true)
  rescue SourceSystems::Manager::Refused => error
    panel_refuse(source_systems_path, error.message)
  end

  private
    def set_system
      @system = SourceSystem.includes(:tenant).find(params[:id])
      authorize @system
    end

    def manageable_tenants = Tenant.where(id: Current.user.tenant_ids_with(SourceSystemPolicy::KEY)).order(:name)

    def manager = SourceSystems::Manager.new(Current.user)

    # A lista (uma linha por sistema, o CRM e o Planilha antes dos remotos) e os cartões da política, só dos credores em que ela decide algo (R410).
    def load_page
      @tenants = manageable_tenants.pluck(:name, :id)
      @several_tenants = @tenants.size > 1
      scope = policy_scope(SourceSystem).includes(:tenant).joins(:tenant)
                .order(Arel.sql("tenants.name, CASE source_systems.role WHEN 'crm' THEN 0 WHEN 'default' THEN 1 ELSE 2 END, lower(source_systems.name)"))
      scope = scope.where(tenant_id: params[:credor]) if params[:credor].present?
      if params[:busca].present?
        scope = scope.where("source_systems.name ILIKE ?", "%#{SourceSystem.sanitize_sql_like(params[:busca].strip)}%")
      end
      @pagination = Pagination.new(scope, page: params[:pagina], per_page: params[:por_pagina])
      @systems = @pagination.records.to_a
      imports = Import.where(source_system_id: @systems.map(&:id)).group(:source_system_id)
      @import_counts = imports.count
      @last_imports = imports.maximum(:created_at)
      @policy_cards = SourceSystems::PolicyCard.for(policy_scope(SourceSystem))
    end
end
