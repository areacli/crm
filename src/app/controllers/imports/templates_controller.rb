module Imports
  # Planilha-modelo (R44): cabeçalho e três linhas fictícias, em CSV com ponto e vírgula (UTF-8), aceita sem alteração na conferência.
  class TemplatesController < ApplicationController
    def show
      authorize Import, :new?
      send_data Portfolio::SheetModel.csv, filename: "modelo-carteira.csv", type: "text/csv; charset=utf-8"
    end
  end
end
