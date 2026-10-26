# Confirmação curta de uma ação sem dados (design system, revisão 4): devolve o modal pequeno (ou, sem JavaScript, uma página) que envia para o destino do token.
class ConfirmationsController < ApplicationController
  def show
    @confirmation = Confirmation.read(params[:token])
    head :not_found unless @confirmation
  end
end
