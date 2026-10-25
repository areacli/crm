# Arquivo de acordos (11, R244): a lista das exportações dos credores em que o usuário tem "administrar acordos" (17), exportar (novidades desde a última exportação manual, ou
# completo) e baixar. O arquivo do dia é gerado todos os dias pela tarefa diária. Os arquivos duram 30 dias. O que o usuário não alcança responde "não encontrado" (R33).
class AgreementExportsController < ApplicationController
  def index
    authorize AgreementExport
    @tenants = Tenant.where(id: Current.user.tenant_ids_with("administer_agreements")).order(:name)
    @exports = policy_scope(AgreementExport).includes(:tenant, :user).recent.limit(50)
    @unseen = Agreements::UnseenEntries.for(@tenants)
  end

  def create
    tenant = Tenant.find(params.expect(agreement_export: %i[tenant_id form])[:tenant_id])
    form = params.expect(agreement_export: %i[tenant_id form])[:form]
    authorize AgreementExport.new(tenant: tenant), :create?
    raise ActionController::BadRequest unless %w[news full].include?(form)

    export = Agreements::Archive.new(tenant).export!(form, user: Current.user)
    redirect_to agreement_exports_path, notice: t(".done", lines: export.lines), status: :see_other
  end

  def show
    export = AgreementExport.find(params[:id])
    authorize export
    return redirect_to(agreement_exports_path, alert: t(".expired"), status: :see_other) unless export.available?

    export.update_columns(downloaded_at: Time.current)
    send_file export.path, filename: "acordos-#{export.tenant.name.parameterize}-#{export.created_at.to_date.iso8601}-#{export.form}.csv", type: "text/csv"
  end
end
