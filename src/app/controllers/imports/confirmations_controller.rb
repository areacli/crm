# Confirma uma importação conferida: a gravação roda em segundo plano e o andamento chega pelo WebSocket.
module Imports
  class ConfirmationsController < ApplicationController
    def create
      import = Import.find(params[:import_id])
      authorize import, :confirm?
      Portfolio::ImportService.new.confirm(import, by: Current.user)
      panel_finish(import_path(import), notice: "Confirmação iniciada.", atualizar: true)
    rescue Portfolio::ImportRefused => error
      panel_refuse(import_path(import), "#{error.message.capitalize}.")
    end
  end
end
