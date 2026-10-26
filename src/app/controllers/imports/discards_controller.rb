# Descarta uma importação conferida: nada do arquivo entra na carteira.
module Imports
  class DiscardsController < ApplicationController
    def create
      import = Import.find(params[:import_id])
      authorize import, :discard?
      Portfolio::ImportService.new.discard(import)
      panel_finish(import_path(import), notice: "Importação descartada. Nada foi gravado na carteira.", atualizar: true)
    rescue Portfolio::ImportRefused => error
      panel_refuse(import_path(import), "#{error.message.capitalize}.")
    end
  end
end
