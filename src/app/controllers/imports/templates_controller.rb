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
        send_data Portfolio::SheetModel.csv, filename: "modelo-carteira.csv", type: "text/csv; charset=utf-8"
      else
        send_data Payments::SheetModel.csv(kind), filename: "modelo-#{kind == 'payments' ? 'pagamentos' : 'estornos'}.csv", type: "text/csv; charset=utf-8"
      end
    end
  end
end
