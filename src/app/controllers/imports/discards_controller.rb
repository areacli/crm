# Descarta uma importação conferida: nada do arquivo entra na carteira.
module Imports
  class DiscardsController < ApplicationController
    def create
      import = Import.find(params[:import_id])
      authorize import, :discard?
      Portfolio::ImportService.new.discard(import)
      redirect_to import, notice: "Importação descartada. Nada foi gravado na carteira."
    rescue Portfolio::ImportRefused => error
      redirect_to import, alert: "#{error.message.capitalize}."
    end
  end
end
