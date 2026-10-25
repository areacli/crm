module Imports
  # Planilha-modelo (R44): cabeçalho e linhas fictícias, em CSV com ponto e vírgula (UTF-8). A da carteira é aceita sem alteração na
  # conferência; as de pagamentos e estornos, quando o canal e os títulos existem.
  class TemplatesController < ApplicationController
    def show
      kind = Import.kinds.key?(params[:kind]) ? params[:kind] : "portfolio"
      authorize Import.new(kind: kind), :new?
      if kind == "portfolio"
        send_data Portfolio::SheetModel.csv, filename: "modelo-carteira.csv", type: "text/csv; charset=utf-8"
      else
        send_data Payments::SheetModel.csv(kind), filename: "modelo-#{kind == 'payments' ? 'pagamentos' : 'estornos'}.csv", type: "text/csv; charset=utf-8"
      end
    end
  end
end
