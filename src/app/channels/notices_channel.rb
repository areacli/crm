# Avisos de um usuário: cada pessoa assina só o canal dela (sem parâmetro, o canal é o do usuário da conexão). A difusão leva só o
# sinal "notice-created"; o sino da casca busca a lista de novo (`spa/aplicacao`).
class NoticesChannel < ApplicationCable::Channel
  def subscribed
    return reject unless current_user

    stream_for current_user
  end
end
