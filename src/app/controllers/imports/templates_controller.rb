module Imports
  # Planilha-modelo (R44): cabeçalho e linhas fictícias, em CSV com ponto e vírgula (UTF-8). A da carteira é aceita sem alteração na
  # conferência; as de pagamentos e estornos, quando o canal e os títulos existem.
  class TemplatesController < ApplicationController
    # Serve página ou arquivo direto, fora da casca (impressão, download, entrada).
    skip_before_action :redirect_page_to_shell
    def show
      kind = FilterValue.from_url(params[:tipo]).presence_in(Import.kinds.keys) || "portfolio"
      authorize Import.new(kind: kind), :new?
      if kind == "portfolio"
        # 17, R401: as colunas de id remoto entram no modelo de quem tem credor com sistema remoto.
        ids = SourceSystem.role_remote.where(tenant_id: Current.user.tenant_ids_with(ImportPolicy::UPLOAD.fetch(kind))).exists?
        send_data Portfolio::SheetModel.csv(ids: ids), filename: "modelo-carteira.csv", type: "text/csv; charset=utf-8"
      else
        # 17, R416 e R417: `sistema` e `id_titulo` entram no modelo de quem tem credor com sistema remoto.
        remote = SourceSystem.role_remote.where(tenant_id: Current.user.tenant_ids_with(ImportPolicy::UPLOAD.fetch(kind))).to_a
        send_data Payments::SheetModel.csv(kind, remote: remote), filename: "modelo-#{kind == 'payments' ? 'pagamentos' : 'estornos'}.csv", type: "text/csv; charset=utf-8"
      end
    end
  end
end
