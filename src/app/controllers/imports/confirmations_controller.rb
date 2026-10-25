# Confirma uma importação conferida: a gravação roda em segundo plano e o andamento chega pelo WebSocket.
module Imports
  class ConfirmationsController < ApplicationController
    def create
      import = Import.find(params[:import_id])
      authorize import, :confirm?
      Portfolio::ImportService.new.confirm(import, by: Current.user)
      redirect_to import, notice: "Confirmação iniciada."
    rescue Portfolio::ImportRefused => error
      redirect_to import, alert: "#{error.message.capitalize}."
    end
  end
end
